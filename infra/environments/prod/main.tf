locals {
  common_labels = {
    env = "prod"
    app = "mbgc"
  }

  # The monorepo holds all services and infra. One WIF binding covers all deploys.
  service_repos = ["mbgc"]

  # Alias kept for clarity — same value, single repo.
  trusted_repos = ["mbgc"]

  runtime_services = toset([
    "mbgc-api",
  ])
}

###############################################################################
# GCP APIs
###############################################################################

resource "google_project_service" "artifactregistry" {
  project            = var.gcp_project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam_credentials" {
  project            = var.gcp_project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = var.gcp_project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

###############################################################################
# Cloud Run runtime service accounts — each service runs as its own identity
# so a compromised container is blast-radius-limited to that service's grants.
###############################################################################

resource "google_service_account" "runtime" {
  for_each     = local.runtime_services
  project      = var.gcp_project_id
  account_id   = "run-${each.key}"
  display_name = "Cloud Run runtime — ${each.key}"
}

###############################################################################
# Cloud Run — services
###############################################################################

# Single public API — validates JWT, handles all business logic.
module "cloud_run_api" {
  source = "../../modules/cloud-run"

  name            = "mbgc-api"
  project         = var.gcp_project_id
  region          = var.gcp_region
  public          = true
  service_account = google_service_account.runtime["mbgc-api"].email
  labels          = local.common_labels
}

###############################################################################
# Artifact Registry
###############################################################################

resource "google_artifact_registry_repository" "mbgc" {
  project       = var.gcp_project_id
  location      = var.gcp_region
  repository_id = "mbgc"
  format        = "DOCKER"
  labels        = local.common_labels
  depends_on    = [google_project_service.artifactregistry]
}

###############################################################################
# Workload Identity Federation — GitHub Actions (keyless auth)
###############################################################################

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.iam_credentials]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # Only repos in local.trusted_repos can mint tokens. Expanding repository_owner
  # (the previous condition) trusts every repo under the org — too broad.
  attribute_condition = "assertion.repository in ${jsonencode([for r in local.trusted_repos : "${var.github_org}/${r}"])}"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

###############################################################################
# Deploy service account — used by each service repo's CI to push images and
# update Cloud Run. Per-repo WIF bindings limit blast radius.
###############################################################################

resource "google_service_account" "deploy" {
  project      = var.gcp_project_id
  account_id   = "github-deploy"
  display_name = "GitHub Actions Deploy"
}

resource "google_project_iam_member" "deploy_run" {
  project = var.gcp_project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_project_iam_member" "deploy_ar" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_project_iam_member" "deploy_sa_user" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_service_account_iam_member" "wif_deploy" {
  for_each           = toset(local.service_repos)
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${each.key}"
}

###############################################################################
# Terraform service account — created by scripts/bootstrap.sh; bound here so
# this repo's CI can run terraform via WIF (no long-lived key).
###############################################################################

data "google_service_account" "terraform" {
  project    = var.gcp_project_id
  account_id = "terraform"
}

resource "google_service_account_iam_member" "wif_terraform" {
  service_account_id = data.google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/mbgc"
}

###############################################################################
# Cloudflare Pages — mbgc-web frontend
###############################################################################

module "pages_mbgc_web" {
  source = "../../modules/cloudflare-pages"

  account_id        = var.cloudflare_account_id
  project_name      = "mbgc-web"
  production_branch = "main"
}

###############################################################################
# Supabase — auth settings
###############################################################################

resource "supabase_settings" "prod" {
  project_ref = var.supabase_project_ref

  auth = jsonencode({
    site_url = "https://lumedina.dev"

    # Allow Pages preview deployments and local dev as redirect targets.
    uri_allow_list = join(",", [
      "https://lumedina.dev",
      "https://*.mbgc-web.pages.dev",
      "http://localhost:5173",
    ])

    # Access token lifetime matches mbgc JWT policy (15 min).
    jwt_expiry = 900

    disable_signup = false

    external_email_enabled             = true
    mailer_autoconfirm                 = false
    mailer_secure_email_change_enabled = true

    refresh_token_rotation_enabled        = true
    security_refresh_token_reuse_interval = 10
  })
}

###############################################################################
# Cloudflare DNS — lumedina.dev
###############################################################################

# Apex → Pages
resource "cloudflare_dns_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "lumedina.dev"
  type    = "CNAME"
  content = "mbgc-web.pages.dev"
  proxied = true
  ttl     = 1 # Cloudflare convention for "auto" when proxied.
}

# www → apex
resource "cloudflare_dns_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www.lumedina.dev"
  type    = "CNAME"
  content = "lumedina.dev"
  proxied = true
  ttl     = 1
}

###############################################################################
# api.lumedina.dev → Cloud Run gateway
#
# Cloud Run routes traffic by the Host header matching its run.app hostname.
# A proxied CF CNAME to the run.app URL arrives with Host: api.lumedina.dev
# and gets a 404 from the Google frontend. Instead we use a Cloud Run custom
# domain mapping (Google terminates TLS for api.lumedina.dev) and point
# Cloudflare DNS-only at ghs.googlehosted.com.
#
# One-time prerequisite: lumedina.dev must be verified in Google Search Console
# for the terraform service account (or for an identity that delegated to it).
# See: https://cloud.google.com/run/docs/mapping-custom-domains#command-line
###############################################################################

resource "google_cloud_run_domain_mapping" "api" {
  name     = "api.lumedina.dev"
  location = var.gcp_region

  metadata {
    namespace = var.gcp_project_id
  }

  spec {
    route_name = module.cloud_run_api.name
  }
}

resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api.lumedina.dev"
  type    = "CNAME"
  content = "ghs.googlehosted.com"
  # DNS-only: Cloud Run, not Cloudflare, terminates TLS for this hostname.
  proxied = false
  ttl     = 300

  depends_on = [google_cloud_run_domain_mapping.api]
}

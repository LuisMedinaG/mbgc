output "pages_subdomain" {
  description = "Cloudflare Pages subdomain for mbgc-web."
  value       = module.pages_mbgc_web.subdomain
}

output "monolith_uri" {
  description = "Cloud Run URL for the monolith."
  value       = module.cloud_run_monolith.uri
}

output "gateway_uri" {
  description = "Cloud Run URL for the API gateway (proxied at api.lumedina.dev)."
  value       = module.cloud_run_gateway.uri
}

output "workload_identity_provider" {
  description = "WIF provider resource name — set as GCP_WORKLOAD_IDENTITY_PROVIDER in each service repo."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deploy_service_account" {
  description = "Deploy SA email — set as GCP_SERVICE_ACCOUNT in each service repo."
  value       = google_service_account.deploy.email
}

output "terraform_service_account" {
  description = "Terraform SA email — set as GCP_TERRAFORM_SERVICE_ACCOUNT on this repo for CI."
  value       = data.google_service_account.terraform.email
}

output "runtime_service_accounts" {
  description = "Runtime SA emails keyed by service name. Each service repo reads its own to pass via --service-account in gcloud run deploy."
  value       = { for k, sa in google_service_account.runtime : k => sa.email }
}

output "artifact_registry" {
  description = "Artifact Registry base URL for Docker images."
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/mbgc"
}

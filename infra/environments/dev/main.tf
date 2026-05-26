locals {
  common_labels = {
    env     = "dev"
    project = "mbgc"
  }
}

# Runtime SA for mbgc-api-dev. Scoped to this service only.
resource "google_service_account" "runtime_api" {
  project      = var.gcp_project_id
  account_id   = "run-mbgc-api-dev"
  display_name = "Cloud Run runtime — mbgc-api-dev"
}

# Cloud Run v2 pulls the container image using the runtime SA.
resource "google_project_iam_member" "runtime_ar_reader" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.runtime_api.email}"
}

module "cloud_run_api" {
  source = "../../modules/cloud-run"

  name                = "mbgc-api-dev"
  project             = var.gcp_project_id
  region              = var.gcp_region
  public              = true
  service_account     = google_service_account.runtime_api.email
  labels              = local.common_labels
  max_instances       = 2
  deletion_protection = false
}

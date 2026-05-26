provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Credentials: WIF via google-github-actions/auth (CI) or ADC (local).
}

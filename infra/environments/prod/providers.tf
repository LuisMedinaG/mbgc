provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Credentials: Workload Identity Federation via google-github-actions/auth (CI)
  # or ADC (local: gcloud auth application-default login).
}

provider "supabase" {
  access_token = var.supabase_access_token
}

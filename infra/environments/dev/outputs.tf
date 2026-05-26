output "api_uri" {
  description = "Cloud Run URL for mbgc-api-dev."
  value       = module.cloud_run_api.uri
}

output "runtime_service_account" {
  description = "Runtime SA email — set as GCP_RUNTIME_SA_API_DEV in GitHub Actions secrets."
  value       = google_service_account.runtime_api.email
}

variable "gcp_project_id" {
  description = "GCP project ID."
  type        = string
  default     = "myboardgamecollection-494214"
}

variable "gcp_region" {
  description = "GCP region for Cloud Run services."
  type        = string
  default     = "us-central1"
}

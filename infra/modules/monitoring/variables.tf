variable "project_id" {
  description = "GCP project ID hosting Cloud Run and Cloud Logging."
  type        = string
}

variable "alert_email" {
  description = "Email address that receives all monitoring alerts. Stored in gitignored terraform.tfvars; CI uses TF_VAR_alert_email."
  type        = string
}

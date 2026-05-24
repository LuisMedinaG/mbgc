variable "name" {
  description = "Cloud Run service name."
  type        = string
}

variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "public" {
  description = "Allow unauthenticated invocations (adds allUsers invoker IAM binding)."
  type        = bool
  default     = false
}

variable "service_account" {
  description = "Email of the runtime SA. Empty uses the default compute SA (has project editor — not recommended)."
  type        = string
  default     = ""
}

variable "invokers" {
  description = "Extra SA emails granted roles/run.invoker. Use for internal services called by other services."
  type        = list(string)
  default     = []
}

variable "max_instances" {
  description = "Maximum number of instances."
  type        = number
  default     = 3
}

variable "labels" {
  description = "Resource labels for cost tracking."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Prevent accidental destroy. Set false for throwaway environments."
  type        = bool
  default     = true
}

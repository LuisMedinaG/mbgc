variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Edit, Pages:Edit, DNS:Edit."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for lumedina.dev."
  type        = string
}

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

variable "supabase_access_token" {
  description = "Supabase personal access token."
  type        = string
  sensitive   = true
}

variable "supabase_project_ref" {
  description = "Supabase project ref (subdomain)."
  type        = string
  default     = "mlltpfszhtxhphoaeydh"
}

variable "github_org" {
  description = "GitHub organization or user owning the mbgc repos."
  type        = string
  default     = "LuisMedinaG"
}

variable "domain" {
  description = "Root domain for the project (e.g. lumedina.dev)."
  type        = string
  default     = "lumedina.dev"
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "project_name" {
  description = "Pages project name."
  type        = string
}

variable "production_branch" {
  description = "Git branch treated as production."
  type        = string
  default     = "main"
}

resource "cloudflare_pages_project" "this" {
  account_id        = var.account_id
  name              = var.project_name
  production_branch = var.production_branch

  lifecycle {
    # All post-creation config (GitHub integration, build settings) is managed
    # via the CF dashboard. Provider v5 sends malformed PATCHes for computed
    # source fields, so ignore everything after initial creation.
    # WARNING: ignore_changes = all means any future in-band changes (e.g. rename)
    # will silently no-op. Destroy + recreate if you need to change a tracked field.
    ignore_changes = all
  }
}

output "subdomain" {
  value = cloudflare_pages_project.this.subdomain
}

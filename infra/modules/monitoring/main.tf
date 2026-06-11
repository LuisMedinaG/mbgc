###############################################################################
# GCP APIs
###############################################################################

resource "google_project_service" "monitoring" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

###############################################################################
# Notification channel — single email sink for all monitoring alerts.
# ref: monitoring.ALERTS.1-5
###############################################################################

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "mbgc monitoring — email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.monitoring]
}

###############################################################################
# Log-based metrics — one counter per alert ACID.
#
# The service emits slog JSON to stdout in Cloud Run. Cloud Logging parses it
# into jsonPayload. Filters below match the `event` field set by the
# `pkg/shared/httpx/Record` helper and the `services/api/internal/observe`
# package.
#
# ref: monitoring.ALERTS.1-4
###############################################################################

# ref: monitoring.ALERTS.1 — event=panic occurrences
resource "google_logging_metric" "panic_count" {
  project = var.project_id
  name    = "panic_count"
  filter  = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"panic\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.logging]
}

# ref: monitoring.ALERTS.2 — event=server_error (numerator of 5xx ratio)
resource "google_logging_metric" "server_error_count" {
  project = var.project_id
  name    = "server_error_count"
  filter  = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"server_error\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.logging]
}

# ref: monitoring.ALERTS.2 — denominator of 5xx ratio. Counts every HTTP
# response: 2xx, 3xx, 4xx-non-401, and 5xx. Excludes auth_failure because that
# signal is its own alert.
resource "google_logging_metric" "request_count" {
  project = var.project_id
  name    = "request_count"
  filter  = "resource.type=\"cloud_run_revision\" AND (jsonPayload.event=\"request\" OR jsonPayload.event=\"server_error\")"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.logging]
}

# ref: monitoring.ALERTS.3 — event=auth_failure on /auth/* paths
resource "google_logging_metric" "auth_failure_count" {
  project = var.project_id
  name    = "auth_failure_count"
  filter  = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"auth_failure\" AND jsonPayload.path=~\"/auth/.*\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.logging]
}

# ref: monitoring.ALERTS.4 — event=rate_limit hits
resource "google_logging_metric" "rate_limit_count" {
  project = var.project_id
  name    = "rate_limit_count"
  filter  = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"rate_limit\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.logging]
}

###############################################################################
# Alert policies
###############################################################################

# ref: monitoring.ALERTS.1 — panic spike > 3 in 5 min
resource "google_monitoring_alert_policy" "panic_spike" {
  project      = var.project_id
  display_name = "mbgc — panic spike (> 3 in 5 min)"
  combiner     = "OR"

  conditions {
    display_name = "panic_count > 3 in 5 min"
    condition_monitoring_query_language {
      query    = <<-EOT
        fetch cloud_run_revision
        | metric 'logging.googleapis.com/user/panic_count'
        | align rate(5m)
        | every 5m
        | group_by []
        | condition val() > 0.01 "1/s"
      EOT
      duration = "0s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  severity              = "ERROR"

  depends_on = [google_monitoring_notification_channel.email]
}

# ref: monitoring.ALERTS.2 — 5xx ratio > 1% over 5 min
# Numerator: server_error_count. Denominator: request_count (includes 2xx-5xx).
# The MQL `div` divides the first aligned series by the second.
resource "google_monitoring_alert_policy" "error_ratio" {
  project      = var.project_id
  display_name = "mbgc — 5xx ratio > 1% over 5 min"
  combiner     = "OR"

  conditions {
    display_name = "server_error / request > 0.01"
    condition_monitoring_query_language {
      query    = <<-EOT
        {
          fetch cloud_run_revision
          | metric 'logging.googleapis.com/user/server_error_count'
          | align rate(5m)
          | every 5m
          | group_by [];
          fetch cloud_run_revision
          | metric 'logging.googleapis.com/user/request_count'
          | align rate(5m)
          | every 5m
          | group_by []
        }
        | ratio
        | condition val() > 0.01
      EOT
      duration = "0s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  severity              = "ERROR"

  depends_on = [google_monitoring_notification_channel.email]
}

# ref: monitoring.ALERTS.3 — auth probe on /auth/* > 5× baseline per 1 min.
# Baseline is approximated as 10 events/min for now; the spec requires "5×
# baseline" but pure MQL has no built-in baseline primitive. Tune by
# observing the natural auth_failure rate in the first week of production
# traffic and bumping this threshold accordingly.
resource "google_monitoring_alert_policy" "auth_probe" {
  project      = var.project_id
  display_name = "mbgc — auth probe on /auth/* > 5× baseline / 1 min"
  combiner     = "OR"

  conditions {
    display_name = "auth_failure_count > 10 in 1 min (5× baseline placeholder)"
    condition_monitoring_query_language {
      query    = <<-EOT
        fetch cloud_run_revision
        | metric 'logging.googleapis.com/user/auth_failure_count'
        | align rate(1m)
        | every 1m
        | group_by []
        | condition val() > 0.167 "1/s"
      EOT
      duration = "0s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  severity              = "WARNING"

  depends_on = [google_monitoring_notification_channel.email]
}

# ref: monitoring.ALERTS.4 — rate-limit flood > 100/min sustained 5 min
resource "google_monitoring_alert_policy" "rate_limit_flood" {
  project      = var.project_id
  display_name = "mbgc — rate-limit flood (> 100/min sustained 5 min)"
  combiner     = "OR"

  conditions {
    display_name = "rate_limit_count > 100/min over 5 min"
    condition_monitoring_query_language {
      query    = <<-EOT
        fetch cloud_run_revision
        | metric 'logging.googleapis.com/user/rate_limit_count'
        | align rate(5m)
        | every 5m
        | group_by []
        | condition val() > 1.667 "1/s"
      EOT
      duration = "300s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  severity              = "WARNING"

  depends_on = [google_monitoring_notification_channel.email]
}

###############################################################################
# Budget alert — Cloud Logging ingestion > 40 GB / month
#
# ref: monitoring.ALERTS.5
#
# Deferred. The `google_billing_budget` resource lives at the billing-account
# level (not the project level), and depends on:
#   1. The billing account ID (not currently in scope of this repo)
#   2. The Cloud Logging service ID in the GCP services catalog (project-specific)
#   3. `roles/billing.costsManager` on the Terraform SA
#
# The 4 monitoring alerts above (ALERTS.1-4) ship in this PR. The budget is
# tracked in the handoff doc as a follow-up that needs billing-account access.
###############################################################################


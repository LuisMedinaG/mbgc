output "notification_channel_id" {
  description = "ID of the email notification channel. Useful for adding the channel to manually-created alerts in the future."
  value       = google_monitoring_notification_channel.email.id
}

output "panic_alert_policy_id" {
  description = "ID of the panic-spike alert policy."
  value       = google_monitoring_alert_policy.panic_spike.id
}

output "error_ratio_alert_policy_id" {
  description = "ID of the 5xx-ratio alert policy."
  value       = google_monitoring_alert_policy.error_ratio.id
}

output "auth_probe_alert_policy_id" {
  description = "ID of the auth-probe alert policy."
  value       = google_monitoring_alert_policy.auth_probe.id
}

output "rate_limit_alert_policy_id" {
  description = "ID of the rate-limit-flood alert policy."
  value       = google_monitoring_alert_policy.rate_limit_flood.id
}

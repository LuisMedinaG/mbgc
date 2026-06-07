# `modules/monitoring`

Cloud Logging + Cloud Monitoring for the mbgc API. Creates the
log-based metrics and alert policies that observe the slog events
emitted by `pkg/shared/httpx/Record` and
`services/api/internal/observe/`.

## Resources created

| Resource | Count | Purpose |
|---|---|---|
| `google_project_service` | 2 | Enable `monitoring` and `logging` APIs |
| `google_monitoring_notification_channel` | 1 | Single email sink for all alerts |
| `google_logging_metric` | 5 | Counters for panic, 5xx, request, auth-failure, rate-limit |
| `google_monitoring_alert_policy` | 4 | Panic spike, 5xx ratio, auth probe, rate-limit flood |

ALERTS.5 (Cloud Logging budget at 40 GB/mo) is **deferred** — see
[the runbook](../../docs/runbook/monitoring.md#6-cost-ceiling-d7)
for what's needed to ship it.

## Inputs

| Name | Description |
|---|---|
| `project_id` | GCP project ID (Cloud Run lives here) |
| `alert_email` | Email address that receives all alerts. Set in `terraform.tfvars` (gitignored) or `TF_VAR_alert_email` in CI. |

## Outputs

| Name | Description |
|---|---|
| `notification_channel_id` | Shared email channel ID |
| `panic_alert_policy_id` | ID of the panic-spike policy |
| `error_ratio_alert_policy_id` | ID of the 5xx-ratio policy |
| `auth_probe_alert_policy_id` | ID of the auth-probe policy |
| `rate_limit_alert_policy_id` | ID of the rate-limit-flood policy |

## How to operate

See [the runbook](../../docs/runbook/monitoring.md) for:
- Where to look in Cloud Logging / Monitoring
- How to tune alert thresholds
- Response playbooks for each alert
- How to add a new alert (spec-first workflow)
- How to disable an alert temporarily
- Cost ceiling and P2 levers

# Monitoring Runbook

How to operate the monitoring pipeline: where to look when something breaks,
how to tune thresholds, and what to do when an alert fires.

The monitoring pipeline emits structured slog events to stdout, which Cloud
Run ships to Cloud Logging, which feeds log-based metrics, which drive
Cloud Monitoring alert policies. End-to-end: code in
`services/api/...` → JSON in Cloud Logging → metrics + alerts in
`infra/modules/monitoring/`.

---

## 1. Where to look first

### Cloud Logging (events)

Go to https://console.cloud.google.com/logs/query?project=myboardgamecollection-494214

Common filters (paste into the query box):

| What you want | Filter |
|---|---|
| All server errors | `jsonPayload.event="server_error"` |
| All panics with stacks | `jsonPayload.event="panic"` |
| All rate-limit rejections | `jsonPayload.event="rate_limit"` |
| Auth failures on `/auth/*` | `jsonPayload.event="auth_failure"` |
| BGG sync lifecycle | `jsonPayload.event=~"sync_(start\|ok\|error)"` |
| Heartbeat (proves service is alive) | `jsonPayload.event="heartbeat"` |
| One specific request | `jsonPayload.request_id="<id>"` |
| All events from one path | `jsonPayload.path="/api/v1/import/sync"` |

Each event also carries `request_id`, `method`, `path`, `status`, and
`latency_ms` — searchable in the Logs Explorer UI.

### Cloud Monitoring (alerts)

Go to https://console.cloud.google.com/monitoring/alerting?project=myboardgamecollection-494214

The 4 alert policies are prefixed with `mbgc —`:
- `mbgc — panic spike (> 3 in 5 min)`
- `mbgc — 5xx ratio > 1% over 5 min`
- `mbgc — auth probe on /auth/* > 5× baseline / 1 min`
- `mbgc — rate-limit flood (> 100/min sustained 5 min)`

Click any policy to see the recent incidents, the MQL query, and the
threshold. The email channel that receives the notification is
`mbgc monitoring — email` (one channel shared by all 4).

---

## 2. Tuning thresholds

All alert thresholds live in `infra/modules/monitoring/main.tf`. To tune:

```sh
cd infra/environments/prod
# Edit the relevant condition_monitoring_query_language block in
# ../../modules/monitoring/main.tf (path is relative to prod/)
terraform plan
terraform apply
```

| Alert | What to change | File path |
|---|---|---|
| Panic spike | `condition_val > 3` in `panic_spike` | `modules/monitoring/main.tf:114` |
| 5xx ratio | `condition_val > 0.01` in `error_ratio` | `modules/monitoring/main.tf:144` |
| Auth probe | `condition_val > 10` in `auth_probe` (placeholder — see §3.3) | `modules/monitoring/main.tf:172` |
| Rate-limit flood | `condition_val > 100` and `duration = "300s"` in `rate_limit_flood` | `modules/monitoring/main.tf:200` |

For MQL frequency (`align`, `every`, `group_by`), see the GCP docs:
https://cloud.google.com/monitoring/mql/reference

---

## 3. Responding to alerts

### 3.1 Panic spike

A recovered panic just got logged with a full stack trace.

1. Open the alert email. It links to the incident and includes a
   `jsonPayload.stack` excerpt.
2. In Cloud Logging, filter for `jsonPayload.event="panic"` and the
   timestamp of the alert. Read the full stack.
3. Decide: one-off or regression?
   - **One-off** (e.g. a request with malformed input that
     `panic(...)`d in a helper): add a unit test, ship a fix.
   - **Regression** (something that was working): revert the last
     Cloud Run deploy (`gcloud run services update-traffic mbgc-api
     --to-revisions=<previous>=100`).
4. The panic also produced a 5xx to the client. Confirm the user
   experience by checking `event=server_error` correlated by
   `request_id` (the panic event and the 5xx event share the
   `request_id` because the `Recover` middleware sets it before
   the panic).

### 3.2 5xx ratio > 1% over 5 min

Sustained server errors.

1. In Cloud Logging, filter `jsonPayload.event="server_error"` and
   group by `path` to find the broken endpoint.
2. Group by `error_code` (set by `httpx.WriteError` from the
   `apierr` sentinel) to narrow down the failure mode.
3. Check the most recent Cloud Run deploy — if the spike started
   within minutes of a deploy, revert (see §3.1 step 3 for the
   command).
4. If no recent deploy, check upstream dependencies (Supabase
   status, BGG API status) for issues.

### 3.3 Auth probe on `/auth/*` > 5× baseline / 1 min

Likely credential-stuffing or a bot enumerating endpoints.

1. In Cloud Logging, filter `jsonPayload.event="auth_failure"` and
   `jsonPayload.path=~"/auth/.*"`.
2. Group by source — but **note: the source IP is not logged** (GDPR
   posture, D9). You cannot identify the attacker from logs alone.
3. Verify the rate limiter is engaging: filter
   `jsonPayload.event="rate_limit"` on the same `/auth/*` paths. If
   rate-limit hits correlate with the auth-failure spike, the
   in-process limiter is doing its job.
4. If the attack is sustained (>15 min) and large (>>100 req/s),
   add a Cloudflare WAF rule blocking the offending ASN or
   fingerprint. Coordinate with the Cloudflare dashboard (out of
   Terraform scope per `infra/AGENTS.md`).
5. **Threshold tuning:** the spec says "5× baseline / 1 min" but
   MQL has no baseline primitive. The placeholder is 10/min. After
   the first week of production, observe the natural
   `auth_failure` rate in Cloud Logging and update
   `condition_val > N` in `auth_probe` accordingly.

### 3.4 Rate-limit flood > 100/min sustained 5 min

Either a misbehaving client or a real attack.

1. In Cloud Logging, filter `jsonPayload.event="rate_limit"` and
   group by `path` to find the hot route.
2. If a single path dominates: identify the client. The
   `request_id` field lets you correlate with the underlying
   request — share that ID with the user who's hitting the limit
   (they have access to it from the response header
   `X-Request-ID`).
3. If multiple paths: likely a bot or shared misbehaving proxy.
   Same response as §3.3 step 4 (Cloudflare WAF).

---

## 4. Adding a new alert

1. **Spec first.** Add an ACID to `features/monitoring.feature.yaml`:
   ```yaml
   ALERTS:
     requirements:
       6: "New condition — fires when X exceeds Y over Z minutes"
   ```
2. **Push spec + run** `npx @acai.sh/cli push --all`. Confirms the
   ACID is registered before you write any code.
3. **Add the log-based metric** in
   `infra/modules/monitoring/main.tf`:
   ```hcl
   resource "google_logging_metric" "new_metric" {
     project = var.project_id
     name    = "new_metric"
     filter  = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"<your_event>\""
     metric_descriptor {
       metric_kind = "DELTA"
       value_type  = "INT64"
     }
   }
   ```
   Add a `// ref: monitoring.ALERTS.6` comment above.
4. **Add the alert policy** that consumes the metric:
   ```hcl
   resource "google_monitoring_alert_policy" "new_alert" {
     # ... full MQL query + condition + severity + channels
   }
   ```
   Add a `// ref: monitoring.ALERTS.6` comment above.
5. **Add outputs** for the new policy in
   `infra/modules/monitoring/outputs.tf` (handy for cross-linking
   in the dashboard).
6. **Validate locally:** `terraform fmt -recursive && tflint --recursive && terraform validate`.
7. **Open a PR** with the changes (target `dev`). PR CI runs the
   plan review.
8. **Merge + apply.** `terraform plan && terraform apply` from
   `infra/environments/prod/`.
9. **Mark ACID completed:** `npx @acai.sh/cli set-status '{"monitoring.ALERTS.6":{"status":"completed"}}' --product mbgc --impl <branch-with-dash>`.

---

## 5. Disabling an alert temporarily

When an alert is firing repeatedly for a known cause and you need
silence to investigate:

```hcl
resource "google_monitoring_alert_policy" "rate_limit_flood" {
  enabled = false  # was: omitted (defaults to true)
  # ... rest of config unchanged
}
```

Apply:
```sh
cd infra/environments/prod
terraform apply
```

The underlying log-based metric keeps accumulating. The alert stops
firing. Re-enable by removing the line (or setting `enabled = true`).

**Alternative — snooze via the GCP UI** (faster, no PR):
Cloud Monitoring → Alerting → click the policy → Snooze. Pick a
duration. Reverts automatically.

---

## 6. Kill switch — disable monitoring entirely

The `MONITORING_DISABLED` env var drops log ingestion from this service to
zero. When set to `true`:

- Every `httpx.Record(...)` call is a no-op (the `Record` helper short-circuits
  on the first instruction).
- All events stop: `request`, `server_error`, `panic`, `rate_limit`,
  `auth_failure`, `sync_start/ok/error`, `heartbeat`.
- The log-based metrics stop accumulating (no events to count), so all four
  alert policies stop firing.
- A single one-time `event=info` line "monitoring disabled via
  MONITORING_DISABLED env var" is emitted at startup so the operator can
  confirm the flag took effect.

### When to use

- Cost ceiling about to be breached (D7) and you need to stop the bleed
  before the budget alert (ALERTS.5) is wired up.
- A noisy log is masking real signal in Cloud Logging.
- A bug is causing runaway event emission (e.g. a tight retry loop that
  logs on every attempt).

### How to flip

```sh
# Disable — service update takes ~5-10 sec, one container restart
gcloud run services update mbgc-api \
  --region=us-central1 \
  --update-env-vars MONITORING_DISABLED=true

# Re-enable
gcloud run services update mbgc-api \
  --region=us-central1 \
  --update-env-vars MONITORING_DISABLED=false
```

No rebuild, no PR, no Terraform change. The flag is read on every
`Record` call via an atomic, so the env var is consulted at startup and
the value stays consistent for the lifetime of the process.

### What you lose

- All alert visibility. If something breaks while disabled, the only
  signal is user complaints or the next deploy.
- The heartbeat, so you can't tell from logs whether the service is
  alive (use the Cloud Run console's "Requests" tab instead).
- Request/response metrics and latency distributions.

### What you don't lose

- The service itself — requests still work normally. `httpx.Record` is on
  the observability path only, not the request path. (See
  `monitoring.FAIL_OPEN.1`.)
- Existing Cloud Logging data — disabling stops new ingestion, not
  retention. Old logs are still queryable.
- Alert policy definitions — they remain in Terraform; re-enabling
  resumes the metric count from zero.

---

## 7. Cost ceiling (D7)

50 GB Cloud Logging free tier per month. At current emission rates,
we're well under (heartbeat = 1 event / 5 min = 8.6k events / month;
a busy day might emit 100k events = ~30 MB / day = 1 GB / month).

**When the budget alert ships (ALERTS.5, deferred — needs billing
account access):** fires at 40 GB / 50 GB = 80% threshold. Re-tune
if/when we approach the ceiling.

**P2 levers (spec change required, not part of P0):**
- Drop heartbeat frequency from 5 min to 15 min (saves 2/3 of
  heartbeat volume).
- Skip logging the `event=request` 4xx-non-401 path entirely
  (these are by far the most common — by skipping them we cut
  volume by an order of magnitude, but lose visibility into
  client error rates).
- Sample high-volume 2xx paths at 10% (keep the metric, lose
  individual event records).

If the budget alert starts firing, open a new feature branch and
spec the change in `features/monitoring.feature.yaml` before
touching the code.

---

## Reference

- **Spec:** `features/monitoring.feature.yaml` (24 ACIDs)
- **Code sinks:** `pkg/shared/httpx/observe.go`,
  `services/api/internal/observe/handler.go`
- **Infra module:** `infra/modules/monitoring/`
- **Handoff history:** `.handoff/monitoring-progress.md`
- **Progress tracker:** see the acai dashboard at
  https://app.acai.sh for current ACID status.

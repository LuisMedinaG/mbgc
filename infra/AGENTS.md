# AGENTS.md — mbgc-infra

Operating rules for AI agents working in this repo.

## Non-negotiable rules

- **Never run `terraform apply`** without first running `terraform plan` and showing the output.
- **Never commit** `terraform.tfvars`, `backend.hcl`, `*.tfstate`, or `*.tfplan`.
- **Never hardcode secrets** in `.tf` files. Sensitive values live in `terraform.tfvars` (gitignored) or `TF_VAR_*` env vars.
- **Always work on a feature branch** — direct pushes to `main` trigger the `apply` job.
- **Keep CI gates green locally before pushing:** `terraform fmt -recursive`, `tflint --recursive`, `tfsec .`. PR CI will block on these.

## Before making any change

1. Run `terraform plan` and check for unexpected destroy/recreate actions — especially:
   - `cloudflare_dns_record` (DNS outage risk)
   - `google_cloud_run_v2_service` (breaks live traffic; `deletion_protection` guards against it by default)
   - `google_cloud_run_domain_mapping.api` (breaks `api.lumedina.dev`)
   - `google_service_account.runtime` (breaks any service running as that identity)
2. If a plan shows a resource will be destroyed and recreated, ask the user to confirm before proceeding.
3. For Cloud Run changes, remember: image / env / resources are ignored here. If the user wants to change those, it's the wrong repo — those live in the service repo's CI/CD.

## Scope

| Managed in this repo | Managed elsewhere |
|---|---|
| Cloud Run service shells (name, ingress, runtime SA, IAM) | Cloud Run image/env/resources — each service repo's `gcloud run deploy` |
| Cloud Run custom domain mapping (`api.lumedina.dev`) | Cloud Run traffic splitting |
| Artifact Registry repo | Image contents |
| Workload Identity Federation pool + provider | GitHub Actions workflow YAML in service repos |
| Runtime + deploy service accounts, IAM roles | |
| Cloudflare Pages project shell | Pages GitHub integration, build settings, env vars (CF dashboard) |
| Cloudflare DNS records | Cloudflare WAF, caching rules |
| Supabase auth settings | Supabase migrations, table schema |

## Security posture (don't regress)

- **WIF condition** is a repo allow-list (`assertion.repository in [...]`). Never broaden to `repository_owner` — that trusts every repo in the org.
- **WIF bindings** are per-repo (`attribute.repository/<org>/<repo>`). Never bind with `attribute.repository_owner`.
- **Cloud Run runtime SAs** are per-service. Never point multiple services at the same runtime SA unless they share a trust boundary.
- **Internal services** (`public = false`) must list the gateway runtime SA in `invokers`. Network-only isolation (INTERNAL ingress) isn't sufficient — Cloud Run still requires IAM `roles/run.invoker`.

## Credentials

Local credentials live in `environments/prod/terraform.tfvars` and `environments/prod/backend.hcl` — both gitignored. Re-run `sh scripts/bootstrap.sh` to regenerate them. The script is idempotent.

The S3 backend (Supabase Storage) needs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` exported before `terraform init` / `plan` / `apply`.

GCP auth:
- **Local:** ADC (`gcloud auth application-default login`).
- **CI:** Workload Identity Federation via `google-github-actions/auth@v2`. No long-lived service account key.

## Provider notes

- `hashicorp/google ~> 6.0` — Cloud Run v2 is used. `google_cloud_run_domain_mapping` is still a v1 resource but works with v2 services. The `cloud-run` module must ignore both `template[0].scaling` **and** top-level `scaling` in `lifecycle.ignore_changes` — removing either re-introduces the perpetual drift loop.
- `cloudflare/cloudflare ~> 5.0` — Pages project uses `lifecycle { ignore_changes = all }` because the provider v5 sends malformed PATCHes for computed `source` fields. Do not remove that block.
- `supabase/supabase ~> 1.5` — only `supabase_settings.auth` is used. Schema is thin; unknown keys are silently dropped.

# mbgc-infra

Terraform source of truth for all `mbgc-*` cloud infrastructure.
One change here = one PR = one audit trail.

> Deep detail lives in [`CLAUDE.md`](./CLAUDE.md) (provider quirks, state backend, conventions) and [`AGENTS.md`](./AGENTS.md) (non-negotiables).

## What this repo manages

| Provider | Resources |
|---|---|
| GCP | Cloud Run services (`myboardgamecollection`, `mbgc-gateway`, `mbgc-auth-service`, `mbgc-game-service`, `mbgc-importer-service`), Artifact Registry `mbgc`, runtime + deploy + terraform service accounts, GitHub WIF, custom domain `api.lumedina.dev` |
| Cloudflare | Pages project `mbgc-web`, DNS for `lumedina.dev` (apex, www, api) |
| Supabase | Auth settings (JWT expiry, site URL, redirects) |

**Not managed here:** Cloud Run images / env vars / resource sizing (service repo CI), Cloudflare Pages build config (CF dashboard), Supabase schema (see [DB migrations](#db-migrations)).

## Stack

- Terraform `>= 1.14` · `hashicorp/google ~> 6.0` · `cloudflare/cloudflare ~> 5.0` · `supabase/supabase ~> 1.5`
- State backend: Supabase Storage (S3-compatible, bucket `mbgc-tfstate`)
- GCP auth: ADC locally, Workload Identity Federation in CI (no long-lived keys)

## Prerequisites

- `terraform >= 1.14`, `gcloud`, `gh`, `aws` CLI
- `gcloud auth login` + `gcloud auth application-default login`
- `gh auth login`

## First-time bootstrap

```sh
sh scripts/bootstrap.sh
```

Idempotent. Provisions the `terraform` GCP SA, writes `backend.hcl` + `terraform.tfvars` (gitignored), syncs GitHub secrets, runs `terraform init`. Prompts for anything missing:

| Value | Source |
|---|---|
| Supabase PAT | app.supabase.com → Account → Access Tokens |
| Supabase S3 key + secret | Supabase → Storage → S3 Connection |
| Cloudflare API token | dash.cloudflare.com → API Tokens (Zone + Pages + DNS edit) |
| Cloudflare zone ID | CF dashboard → `lumedina.dev` → Overview |

**Run it twice on a cold setup:** once before `terraform apply` (creates the SA), once after (pushes `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_TERRAFORM_SERVICE_ACCOUNT` from terraform outputs).

**One-time domain verification for `api.lumedina.dev`:** verify `lumedina.dev` in [Google Search Console](https://search.google.com/search-console/) (TXT record via Cloudflare), then add the terraform SA email as an owner under Settings → Users and permissions. Required before Cloud Run creates the domain mapping.

## Daily workflow

```sh
cd environments/prod
export AWS_ACCESS_KEY_ID=<supabase-s3-key>
export AWS_SECRET_ACCESS_KEY=<supabase-s3-secret>

terraform fmt -recursive
tflint --recursive
tfsec .
terraform plan      # always review
terraform apply
sh ../../scripts/smoke.sh
```

Never `apply` without reviewing the plan. All four gates (`fmt`, `tflint`, `tfsec`, `plan`) must pass locally before pushing — CI runs the same checks.

## CI

`.github/workflows/terraform.yml` — on PR / push to `main` / manual dispatch:

```
fmt → tflint → tfsec → plan  →  (merge to main) → apply → smoke.sh
```

- `plan` uses `-detailed-exitcode`; posts a single updating PR comment.
- `apply` is gated by the `production` GitHub Environment (required reviewers).
- `smoke.sh` verifies Cloud Run services exist, `api.lumedina.dev` resolves, gateway returns non-5xx.

`.github/workflows/drift.yml` — Mon 09:00 UTC. Opens/updates a `drift`-labeled issue when state diverges. Dismiss with `terraform apply` or by updating config.

## End-to-end deploy (service repos)

Each service repo (`mbgc-gateway`, `mbgc-auth-service`, …) owns its own deploy:

```
push to main → GitHub Actions:
  1. Auth to GCP via WIF (secrets set by set-deploy-secrets.sh)
  2. docker build → push to Artifact Registry us-central1-docker.pkg.dev/.../mbgc/<service>
  3. gcloud run deploy <service> --image <sha>
```

The Cloud Run *service* is created by this repo; the *image* and env vars are updated by the service repo. Terraform ignores `template.containers.image` and env changes via `lifecycle`.

After the first `terraform apply`, propagate WIF secrets to all service repos:

```sh
sh scripts/set-deploy-secrets.sh
```

Sets `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_SERVICE_ACCOUNT` on every repo in `local.service_repos`.

## DB migrations

Supabase schema is **not** managed by this repo.

- SQL migrations: `myboardgamecollection/supabase/` (source of truth for the shared Postgres schema).
- Apply via Supabase CLI or dashboard SQL editor — no Terraform resource for schema.
- Auth *settings* (JWT expiry, site URL, redirects) are managed here via `supabase_settings`.

## Adding a new service

1. Feature branch.
2. Add the name to `local.runtime_services` and `local.service_repos` in `environments/prod/main.tf`.
3. Add a `module "cloud_run_<name>"` block. Internal-only? Pass `invokers = [google_service_account.runtime["mbgc-gateway"].email]`.
4. Open PR → review plan → merge.
5. `sh scripts/set-deploy-secrets.sh` to wire WIF into the new repo.
6. Service repo adds its own `deploy.yml` (copy from `mbgc-gateway`).

## GitHub secrets (managed by bootstrap)

| Secret | Purpose |
|---|---|
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | Supabase S3 state backend |
| `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_ZONE_ID` | Cloudflare provider |
| `SUPABASE_ACCESS_TOKEN` | Supabase provider |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_TERRAFORM_SERVICE_ACCOUNT` | WIF auth (from terraform output) |

## Inspecting remote state

```sh
aws --profile supabase s3 ls s3://mbgc-tfstate/prod/
aws --profile supabase s3 cp s3://mbgc-tfstate/prod/terraform.tfstate -
```

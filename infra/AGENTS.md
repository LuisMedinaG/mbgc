# AGENTS.md — mbgc-infra

Terraform source of truth for all mbgc cloud infrastructure. One change = one PR = one audit trail.

## Stack

- **IaC:** Terraform >= 1.14
- **State backend:** Supabase Storage S3-compatible, bucket `mbgc-tfstate`
- **Providers:** `hashicorp/google ~> 6.0` · `cloudflare/cloudflare ~> 5.0` · `supabase/supabase ~> 1.5`

## Layout

```
environments/prod/      # root module — prod is the only env
  main.tf               # resource declarations
  variables.tf
  versions.tf           # provider pins + S3 backend config
  providers.tf
  outputs.tf
  terraform.tfvars      # gitignored — written by bootstrap.sh
  backend.hcl           # gitignored — written by bootstrap.sh
modules/
  cloud-run/            # reusable: google_cloud_run_v2_service + IAM
  cloudflare-pages/     # reusable: cloudflare_pages_project
scripts/
  bootstrap.sh          # idempotent: GCP SA, local files, GitHub secrets, terraform init
  smoke.sh              # post-apply smoke tests (Cloud Run, DNS, gateway HTTPS)
```

## Managed resources

| Provider | Resources |
|---|---|
| GCP Cloud Run | `myboardgamecollection` (monolith, decommissioning), `mbgc-gateway`, `mbgc-game-service`, `mbgc-importer-service`, `mbgc-auth-service` |
| Cloudflare | Pages project, DNS records for `lumedina.dev` (apex, www, api) |
| Supabase | Auth settings (`supabase_settings`) — JWT expiry, site URL, redirect URIs, session policy |

**Not managed here:** Cloud Run image/env/resources (owned by service CI/CD). Cloudflare Pages build settings (CF dashboard, `lifecycle { ignore_changes = all }`).

## Workflow

```sh
cd environments/prod
export AWS_ACCESS_KEY_ID=<supabase-s3-key>
export AWS_SECRET_ACCESS_KEY=<supabase-s3-secret>
terraform plan    # always review first
terraform apply
```

## Inspecting state

```sh
aws --profile supabase s3 ls s3://mbgc-tfstate/prod/
aws --profile supabase s3 cp s3://mbgc-tfstate/prod/terraform.tfstate -
```

Use `-` for stdout. Curl with `-u` won't work — Supabase S3 requires SigV4 signing.

## Bootstrap

```sh
sh scripts/bootstrap.sh
```

Idempotent. Run **twice** on first setup: once before `apply` (creates GCP SA), once after (reads WIF outputs → pushes `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_TERRAFORM_SERVICE_ACCOUNT` to GitHub).

IAM roles on the Terraform SA: `run.admin`, `iam.serviceAccountUser`, `iam.serviceAccountAdmin`, `iam.workloadIdentityPoolAdmin`, `artifactregistry.admin`, `resourcemanager.projectIamAdmin`, `serviceusage.serviceUsageAdmin`

## CI

Terraform changes are **applied manually** — there is no automated `terraform apply` workflow.

- **`ci.yml`** (root monorepo) — on PR/push: `terraform fmt -check -recursive` + `tflint` for lint gates only. Does not plan or apply.
- **No `terraform.yml` or `drift.yml`** — these were planned but not implemented. Apply manually via `terraform plan && terraform apply` from `environments/prod/`.

## Tests

- **`smoke.sh`** — verifies Cloud Run services exist in `us-central1`, `api.lumedina.dev` resolves, gateway returns non-5xx. Override with `GCP_PROJECT`, `GCP_REGION`, `API_HOST`.
- **`tflint`** — terraform preset + google ruleset (`.tflint.hcl`)
- **`tfsec`** — silence intentional false positives with inline `# tfsec:ignore:<rule-id>`

## Non-negotiable rules

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

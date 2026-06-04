# CI/CD Runbook

## Workflow overview

```
PR opened/updated
  ├── branch-check   (PR only — enforces merge path rules)
  ├── go             (build + test + vet)
  ├── web            (lint + build)
  └── infra-lint     (terraform fmt + tflint)

Push to dev
  ├── go ──────────► deploy-api-dev   (migrate dev DB → deploy Cloud Run: mbgc-api-dev)
  ├── web            (lint + build, no web deploy on dev)
  └── infra-lint

Push to main
  ├── go ──────────► deploy-api-prod  (migrate prod DB → deploy Cloud Run: mbgc-api)
  ├── web ─────────► deploy-web       (Cloudflare Pages: mbgc-web)
  └── infra-lint
```

All jobs live in `.github/workflows/pipeline.yml`. Deploy jobs have `needs: go` or `needs: web` — they cannot run unless CI passes.

## Database migrations

Migrations run automatically as part of every API deploy (inside `deploy-cloud-run.yml`, before the Cloud Run deploy). All migration SQL uses `IF NOT EXISTS` / `CREATE OR REPLACE` — safe to run every time.

**Dev vs prod Supabase:**

| Environment | Who runs migrations | Database |
|---|---|---|
| Local dev | `make db-migrate` (manual) | Local Supabase at `:54322` |
| Dev cloud (`mbgc-api-dev`) | CI on push to `dev` | `DEV_API_DATABASE_URL` secret → dev Supabase project |
| Prod cloud (`mbgc-api`) | CI on push to `main` | `API_DATABASE_URL` secret → prod Supabase project |

The API does **not** run migrations on boot — it only connects to the pool. Migrations are a CI concern.

If you need to apply a migration manually (e.g. hotfix, rollback):
```sh
# Against prod:
psql "$API_DATABASE_URL" -f services/api/migrations/NNN_name.up.sql

# Against dev:
psql "$DEV_API_DATABASE_URL" -f services/api/migrations/NNN_name.up.sql
```

## Branch protection sync

When you rename a job in `pipeline.yml`, GitHub branch protection still references the old name and will block all PRs. Run:

```sh
make sync-branch-protection
```

A Claude hook will remind you automatically whenever `pipeline.yml` is edited.

Supporting workflows (not for day-to-day development):

| Workflow | Trigger | Purpose |
|---|---|---|
| `infra.yml` | PR/push to main (infra/ changes) | Terraform plan (PR) / apply (push) |
| `e2e.yml` | Manual (workflow_dispatch) | Playwright tests against a live env |
| `deploy-cloud-run.yml` | Called by pipeline.yml | Reusable Cloud Run deploy logic |

## Triggering a manual deploy

To force-deploy without a code change:

1. Go to **Actions → Pipeline**
2. Click **Run workflow**, select the branch (`dev` or `main`)
3. Click **Run workflow**

## Required GitHub secrets

Set in **Settings → Secrets and variables → Actions → Secrets**.

### GCP (shared, prod + dev)

| Secret | Description |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | WIF provider resource name |
| `GCP_SERVICE_ACCOUNT` | CI deploy service account email |
| `GCP_PROJECT_ID` | GCP project ID |
| `GCP_RUNTIME_SA_API` | Cloud Run runtime SA — prod |
| `GCP_RUNTIME_SA_API_DEV` | Cloud Run runtime SA — dev |
| `GCP_TERRAFORM_SERVICE_ACCOUNT` | SA used by infra.yml for Terraform |

### API — prod

| Secret | Description |
|---|---|
| `API_DATABASE_URL` | Supabase session-mode connection string |
| `API_SUPABASE_URL` | Supabase project URL |
| `API_SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key |
| `API_ALLOWED_ORIGIN` | CORS allowed origin (e.g. `https://mbgc.lumedina.dev`) |
| `API_SEED_ADMIN_EMAIL` | (optional) admin seed email |
| `API_SEED_ADMIN_PASSWORD` | (optional) admin seed password |
| `API_SEED_ADMIN_USERNAME` | (optional) admin seed username |

### API — dev

Same names as prod, prefixed with `DEV_`:

`DEV_API_DATABASE_URL`, `DEV_API_SUPABASE_URL`, `DEV_API_SUPABASE_SERVICE_ROLE_KEY`,
`DEV_API_ALLOWED_ORIGIN`, `DEV_API_SEED_ADMIN_EMAIL`, `DEV_API_SEED_ADMIN_PASSWORD`, `DEV_API_SEED_ADMIN_USERNAME`

### Cloudflare

| Secret | Description |
|---|---|
| `CLOUDFLARE_API_TOKEN` | API token with Cloudflare Pages edit permission |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |

### Terraform backend (R2 / S3-compatible)

| Secret | Description |
|---|---|
| `TF_BACKEND_ACCESS_KEY` | Backend access key |
| `TF_BACKEND_SECRET_KEY` | Backend secret key |
| `TF_VAR_CLOUDFLARE_ZONE_ID` | Cloudflare zone ID |
| `TF_VAR_SUPABASE_ACCESS_TOKEN` | Supabase personal access token |

## Required GitHub variables

Set in **Settings → Secrets and variables → Actions → Variables**.

| Variable | Description |
|---|---|
| `VITE_API_BASE_URL` | Public API URL for the prod web build (e.g. `https://api.lumedina.dev`) |

## Common failures

### `permission denied` on image push
The CI service account needs `roles/artifactregistry.writer` on the Artifact Registry repo.
Run `infra/scripts/bootstrap.sh` or grant the role manually:
```sh
gcloud artifacts repositories add-iam-policy-binding mbgc \
  --location=us-central1 --project=<PROJECT_ID> \
  --member="serviceAccount:<CI_SA>" \
  --role="roles/artifactregistry.writer"
```

### Cloud Run deploy rejected (permission denied)
The CI SA has `roles/run.developer`, not `roles/run.admin`. It can update existing services but **cannot create new ones**. New Cloud Run services must be created via Terraform first.

### Web deploy fails: Cloudflare authentication error
Verify `CLOUDFLARE_API_TOKEN` has **Cloudflare Pages: Edit** permission scoped to the `mbgc-web` project.

### Go tests pass locally but fail in CI
Ensure `go.work` and all `go.sum` files are committed. Run `make tidy` in the repo root and commit any changes.

### Terraform plan fails: backend init error
The R2 backend credentials (`TF_BACKEND_ACCESS_KEY` / `TF_BACKEND_SECRET_KEY`) may be expired or missing. Rotate via `infra/scripts/rotate-secrets.sh cloudflare` and re-sync with `bootstrap.sh`.

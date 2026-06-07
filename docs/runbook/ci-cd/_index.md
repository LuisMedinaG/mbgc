# CI/CD Runbook

## Workflow overview

```
PR opened/updated
  ├── branch-check   (PR only — enforces merge path rules)
  ├── go             (build + test + vet)
  ├── web            (lint + build)
  └── infra-lint     (terraform fmt + tflint)

Push to dev
  ├── go ──────────► deploy-api-dev   (deploy Cloud Run: mbgc-api-dev; migrations run at startup)
  ├── web            (lint + build, no web deploy on dev)
  └── infra-lint

Push to main
  ├── go ──────────► deploy-api-prod  (deploy Cloud Run: mbgc-api; migrations run at startup)
  ├── web ─────────► deploy-web       (Cloudflare Pages: mbgc-web)
  └── infra-lint
```

All jobs live in `.github/workflows/pipeline.yml`. Deploy jobs have `needs: go` or `needs: web` — they cannot run unless CI passes.

## Database protection

Three layers prevent accidental schema changes to prod:

### 1. GitHub Environment approval gate (primary protection)

`deploy-api-prod` is tagged `environment: production`. Before migrations or deploy run, GitHub pauses the job and sends a notification to required reviewers. **One-time setup required:**

1. Go to **Settings → Environments → New environment** → name it `production`
2. Enable **Required reviewers** → add yourself
3. Optionally enable **Deployment branch: main only**

After this, every prod deploy waits for your explicit approval in the GitHub Actions UI.

Dev deploys (`deploy-api-dev`) run automatically — dev is a sandbox.

### 2. Schema backup artifact

Before every migration runs, CI captures `pg_dump --schema-only` and uploads it as a GitHub Actions artifact (retained 30 days, named `schema-backup-<sha>`). To restore after a bad migration:

```sh
# Download the artifact from the Actions run, then:
psql "$DATABASE_URL" -f schema-backup.sql
```

### 3. Emergency skip

If you need to deploy without running migrations (e.g. rollback to an older image that is schema-compatible):

Set `SKIP_MIGRATIONS=true` in the Cloud Run service environment variables before deploying:

```sh
gcloud run services update mbgc-api --region=us-central1 \
  --set-env-vars "SKIP_MIGRATIONS=true"
```

Remove it after the deploy to re-enable migrations on the next boot.

---

**Dev vs prod Supabase:**

| Environment | Who runs migrations | Database |
|---|---|---|
| Local dev | auto on `make dev` (server startup) or `make db-migrate` (manual) | Local Supabase at `:54322` |
| Dev cloud (`mbgc-api-dev`) | auto on deploy (server startup via golang-migrate) | `DEV_API_DATABASE_URL` → dev Supabase project |
| Prod cloud (`mbgc-api`) | auto on deploy (server startup via golang-migrate, after approval) | `API_DATABASE_URL` → prod Supabase project |

The API **runs migrations at startup** via golang-migrate (SQL files embedded in binary, version tracked in `schema_migrations` table). No separate migration step in CI.

If you need to apply a migration manually against a live DB (e.g. hotfix, rollback):
```sh
# Against prod:
migrate -path services/api/migrations -database "$API_DATABASE_URL" up

# Against dev:
migrate -path services/api/migrations -database "$DEV_API_DATABASE_URL" up
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

# Deployment

## Production targets

| Component | Provider | URL |
|---|---|---|
| `services/api` | GCP Cloud Run (`us-central1`) | `mbgc-api-*.run.app` |
| API custom domain | GCP + Cloudflare | `https://api.lumedina.dev` |
| Web frontend | Cloudflare Pages | `https://lumedina.dev` |
| Postgres | Supabase | (private) |

## How deploys work

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | PR / push to `dev`/`main` | Build + test + lint |
| `deploy.yml` | Push to `main` | Deploys API + web (path-filtered) |
| `infra.yml` | PR to `main` | `terraform plan` (comment on PR) |
| `infra.yml` | Merge to `main` | `terraform apply --auto-approve` |

The `services/api` Docker build context is the repo root (to include `pkg/shared`). See `services/api/deploy/Dockerfile`.

## GitHub Secrets

All secrets live on `LuisMedinaG/mbgc`. Provisioned by bootstrap:

```sh
sh infra/scripts/bootstrap.sh
```

| Secret | Source | Used by |
|---|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `terraform output` | `deploy.yml` |
| `GCP_SERVICE_ACCOUNT` | `terraform output` | `deploy.yml` |
| `GCP_PROJECT_ID` | constant | `deploy.yml` |
| `GCP_RUNTIME_SA_API` | `terraform output` | `deploy.yml` |
| `CLOUDFLARE_API_TOKEN` | prompted | `deploy.yml` web job |
| `CLOUDFLARE_ACCOUNT_ID` | prompted | `deploy.yml` web job |
| `TF_BACKEND_ACCESS_KEY` | prompted | `infra.yml` |
| `TF_BACKEND_SECRET_KEY` | prompted | `infra.yml` |

Verify: `gh secret list --repo LuisMedinaG/mbgc`

To rotate any secret: `make rotate-secrets`

## Cloud Run env vars (production)

Terraform does not manage Cloud Run env vars — set them directly:

```sh
gcloud run services update mbgc-api \
  --region us-central1 \
  --project myboardgamecollection-494214 \
  --set-env-vars \
    SUPABASE_URL=https://mlltpfszhtxhphoaeydh.supabase.co,\
    DATABASE_URL=<connection-string>,\
    ALLOWED_ORIGIN=https://lumedina.dev,\
    SUPABASE_SERVICE_ROLE_KEY=<key>,\
    SYNC_LIMIT_USER=3,\
    SYNC_LIMIT_ADMIN=20
```

To scale:
```sh
gcloud run services update mbgc-api \
  --region us-central1 \
  --min-instances=0 \
  --max-instances=5
```

## Terraform (infrastructure changes)

Terraform manages: Cloud Run service shell, Cloudflare DNS/Pages, Artifact Registry, Workload Identity Federation, Supabase auth settings.

**Not managed by Terraform:** Cloud Run images, env vars, resource limits (owned by CI/CD).

```sh
# Set Supabase S3 backend credentials first
export AWS_ACCESS_KEY_ID=<supabase-s3-key>
export AWS_SECRET_ACCESS_KEY=<supabase-s3-secret>

cd infra/environments/prod
terraform plan     # always review before applying
terraform apply
sh ../scripts/smoke.sh   # verify after apply
```

Re-run bootstrap after apply to sync new Terraform outputs to GitHub secrets:

```sh
sh infra/scripts/bootstrap.sh
```

## Manually trigger a deploy

```sh
gh workflow run deploy.yml --ref main
gh run watch
```

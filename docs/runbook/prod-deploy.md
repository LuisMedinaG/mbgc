# Production Deployment Runbook

Use this for every release — not SETUP.md (that's first-time bootstrap only).

## Prerequisites

- `supabase` CLI installed and linked: `supabase link --project-ref mlltpfszhtxhphoaeydh`
- `gh` CLI authenticated
- PR targeting `main` with all CI checks green

---

## Checklist

### 1. Verify CI is green

```sh
gh pr view <PR#> --json statusCheckRollup | jq '[.statusCheckRollup[] | {name,conclusion}]'
```

All required checks must be `SUCCESS` (deploy-api-prod and terraform-apply are `SKIPPED` on PRs — that's expected).

### 2. Push DB migrations to prod

**Always run this before merging.** Migrations are NOT automated by CI/CD.

```sh
# Confirm linked to the right project
supabase projects list

# Dry-run: see what will be applied
supabase db push --dry-run

# Apply
supabase db push
```

If `supabase db push` fails with auth error, re-link:
```sh
supabase login --token <personal-access-token>
supabase link --project-ref mlltpfszhtxhphoaeydh
```

If no new migrations exist, skip this step.

### 3. Merge PR to main

```sh
gh pr merge <PR#> --squash --delete-branch
```

Or merge via GitHub UI. CI/CD will automatically trigger:
- `deploy-api-prod` — builds and deploys to Cloud Run
- `terraform apply` — applies any infra changes

### 4. Monitor deployment

```sh
gh run list --branch main --limit 5
gh run watch   # stream the active run
```

Or watch in GitHub Actions UI.

### 5. Verify health check

```sh
curl -s https://api.lumedina.dev/readyz | jq .
```

Expected: `{"status":"ok"}`

### 6. Verify admin seed (first deploy or after credential rotation)

Check Cloud Run logs for:
```
INFO admin user ready email=<SEED_ADMIN_EMAIL>
```

```sh
gcloud run services logs read mbgc-api --region=us-central1 --limit=50 | grep -i admin
```

### 7. Smoke test

- [ ] Log in with admin credentials at the web app
- [ ] Confirm `/api/v1/auth/ping` returns 200
- [ ] Confirm collection page loads

---

## Rollback

```sh
# Roll back API to the previous image (get tag from prior successful run)
gcloud run services update mbgc-api \
  --region=us-central1 \
  --image=us-central1-docker.pkg.dev/<project>/mbgc/api:<previous-sha>
```

DB migrations cannot be auto-rolled back — run the `.down.sql` manually via Supabase SQL editor if needed.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `supabase db push` fails with 401 | Re-run `supabase login` + `supabase link` |
| Cloud Run deploy fails | Check `gh run watch` for build errors |
| Health check returns 500 | Check Cloud Run logs: `gcloud run services logs read mbgc-api --region=us-central1` |
| Admin seed not running | Verify `API_SEED_ADMIN_EMAIL` secret is set in GitHub → Settings → Secrets |
| Terraform drift after deploy | Run `terraform plan` in `infra/environments/prod` to inspect |

# mbgc — Setup Guide

Single source of truth for getting mbgc running from scratch.

## Prerequisites

- Go 1.25+, Bun, Docker (for Supabase), Terraform 1.5+
- Supabase CLI: `brew install supabase/tap/supabase`
- GitHub CLI: `brew install gh`
- gcloud CLI (prod only): `brew install --cask google-cloud-sdk`

---

## Local development

### 1. Clone and configure

```sh
git clone git@github.com:LuisMedinaG/mbgc.git
cd mbgc
make setup-local       # creates services/api/.env from .env.example
```

On first run, `setup-local` exits after creating `.env` so you can fill it in.

### 2. Fill in services/api/.env

```sh
# Start Supabase to get keys
supabase start

# supabase status will show:
#   Publishable key → SUPABASE_ANON_KEY
#   Service role key → SUPABASE_SERVICE_ROLE_KEY
```

Minimum required values:

| Variable | Where to find it |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | `supabase status` → Secret |
| `SEED_ADMIN_EMAIL` | Your choice |
| `SEED_ADMIN_PASSWORD` | Your choice (min 6 chars) |

Leave `SUPABASE_JWT_SECRET` empty (JWKS-only is preferred).

### 3. Finish setup

```sh
make setup-local       # runs migrations
make dev               # starts API (port 8080) + web (port 5173) in tmux
```

The API creates the admin user on **first boot** — check the logs:
```
INFO admin user ready email=you@example.com
```

After that, `SEED_ADMIN_EMAIL` and `SEED_ADMIN_PASSWORD` can remain set — they're idempotent and do nothing once the user exists.

### Daily workflow

```sh
make dev               # start API + web
make db-migrate        # apply new migrations
make test              # run Go tests
make lint              # lint everything
make db-reset          # wipe + replay migrations (local only)
```

---

## Production setup

### 1. Bootstrap infrastructure (once)

```sh
cd infra
bash scripts/bootstrap.sh
```

This creates:
- GCP project, Artifact Registry, Cloud Run service shell
- Cloudflare DNS + Pages
- Supabase project link
- GitHub Actions secrets

Run it twice on initial setup — first pass creates the GCP service account,
second pass extracts outputs and syncs secrets to GitHub.

### 2. Run migrations against prod

After bootstrap, push migrations from local (linked project):

```sh
supabase link --project-ref <your-project-ref>
supabase db push
```

### 3. Seed admin user in prod

Set env vars on the Cloud Run service **once**:

```sh
gcloud run services update mbgc-api \
  --region=us-central1 \
  --set-env-vars "SEED_ADMIN_EMAIL=you@example.com,SEED_ADMIN_PASSWORD=yourpassword,SUPABASE_SERVICE_ROLE_KEY=your-key"
```

Deploy → the API creates the admin user on first boot.

After confirming login works, **remove the seed vars**:

```sh
gcloud run services update mbgc-api \
  --region=us-central1 \
  --remove-env-vars "SEED_ADMIN_EMAIL,SEED_ADMIN_PASSWORD"
```

### 4. CI/CD (ongoing)

- Push to a `feature/*` branch → CI runs (build, test, lint)
- Open PR to `dev` → infra plan comment posted automatically
- Merge to `dev` → CI gate
- Merge `dev → main` → deploy + infra apply runs automatically

---

## Changing app or service versions

Service image versions are managed by CI/CD (build on push, tag with git SHA).
To pin or override a version manually:

```sh
gcloud run services update mbgc-api \
  --region=us-central1 \
  --image=us-central1-docker.pkg.dev/<project>/mbgc/api:<tag>
```

To scale up/down:

```sh
gcloud run services update mbgc-api \
  --region=us-central1 \
  --min-instances=0 \
  --max-instances=5
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `db ping failed` | Run `supabase start` first |
| `admin seed skipped: SUPABASE_SERVICE_ROLE_KEY not set` | Add key to `.env` |
| `jwt verifier init failed` | Check `SUPABASE_URL` is reachable |
| Migrations fail on prod | Ensure `supabase link` ran first |
| CORS errors in browser | Set `ALLOWED_ORIGIN` to your web URL |

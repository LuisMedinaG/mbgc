# mbgc — Setup Guide

Single source of truth for getting mbgc running from scratch.

## Prerequisites

- Go 1.25+, Bun, Docker (for Supabase), Terraform 1.5+
- Supabase CLI: `brew install supabase/tap/supabase`
- GitHub CLI: `brew install gh`
- gcloud CLI (prod only): `brew install --cask google-cloud-sdk`

---

## Local development

### 1. Clone and start Supabase

```sh
git clone git@github.com:LuisMedinaG/mbgc.git
cd mbgc
supabase start         # boots local Postgres + Auth (Docker required)
supabase status        # prints URLs and keys — keep this open
```

### 2. Create and fill in services/api/.env

```sh
make setup-local       # creates services/api/.env from .env.example, then exits
```

Open `services/api/.env`. `DATABASE_URL` and `SUPABASE_URL` are **already correct for local** — do not change them. Fill in only these three:

| Variable | Value |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | `supabase status` → **Secret** key |
| `SEED_ADMIN_EMAIL` | Your choice (e.g. `you@example.com`) |
| `SEED_ADMIN_PASSWORD` | Your choice (min 6 chars) |

> **Key naming:** the Supabase CLI now labels keys **Publishable** (anon) and **Secret** (service_role).
> Use the **Secret** key for `SUPABASE_SERVICE_ROLE_KEY`.
> Leave `SUPABASE_JWT_SECRET` empty — JWKS-only ES256 is the default and recommended.

### 3. Run migrations and start

```sh
make setup-local       # Supabase already running, applies all migrations
make dev               # starts API (port 8080) + web (port 5173) in tmux
```

The API creates the admin user on **first boot** — check the logs:
```
INFO admin user ready email=you@example.com
```

`SEED_ADMIN_EMAIL` and `SEED_ADMIN_PASSWORD` are safe to leave set — they're idempotent and do nothing once the user exists.

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

# Troubleshooting

## API won't start

| Symptom | Fix |
|---|---|
| `required env var not set key=SUPABASE_URL` | Fill in `services/api/.env` |
| `required env var not set key=DATABASE_URL` | Fill in `services/api/.env` |
| `init JWKS from ...` error on startup | `SUPABASE_URL` wrong or unreachable — API fetches JWKS at boot |
| `db ping failed` | Run `supabase start` first |
| `bind: address already in use` | `lsof -ti:8080 \| xargs kill -9` |
| `admin seed skipped: SUPABASE_SERVICE_ROLE_KEY not set` | Add key to `.env` (from `supabase status` → Secret) |

## Web won't start

| Symptom | Fix |
|---|---|
| `vite: command not found` | `cd web && bun install` |
| CORS errors in browser | Set `ALLOWED_ORIGIN` in `services/api/.env` to `http://localhost:5173` |

## Database

| Symptom | Fix |
|---|---|
| `failed to connect to database` | Check `DATABASE_URL` in `.env`; verify Supabase is running |
| Migrations fail on prod | Run `supabase link --project-ref <ref>` first |
| `relation "profile.users" does not exist` | Run `make db-migrate` |

## Go / modules

```sh
go work sync
make -C services/api tidy
```

Check `go.work` lists both modules: `cat go.work`

## Terraform

| Symptom | Fix |
|---|---|
| `401: Unauthorized` on `supabase_settings` | Rotate Supabase access token: `make rotate-secrets supabase` |
| `terraform init` fails with S3 error | Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (Supabase S3 creds) |
| Perpetual drift on Cloud Run `scaling` | Expected — `lifecycle.ignore_changes` covers this; don't remove it |

## CI

| Symptom | Fix |
|---|---|
| `tflint` fails | Run `tflint --chdir=infra` locally to debug |
| `eslint` fails | Run `make lint` in `web/` locally |
| Docker build: `cmd/server not found` | Ensure `services/api/cmd/server/main.go` is committed (check `git status`) |
| WIF auth fails in CI | Verify `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` secrets are set |

## Secret rotation

Use `make rotate-secrets` — see [SETUP.md](../SETUP.md) for per-secret instructions.

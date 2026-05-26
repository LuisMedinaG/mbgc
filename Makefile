.PHONY: setup-local setup-prod dev db-migrate db-reset test lint build \
        rotate-secrets acai-push acai-status acai-features help

# Root Makefile — mbgc monorepo
# Run `make help` to see all targets.

ENV_FILE := services/api/.env

# ── First-time setup ─────────────────────────────────────────────────────────

## setup-local: First-time local dev setup (copies .env, starts Supabase, migrates)
setup-local:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		cp services/api/.env.example $(ENV_FILE); \
		echo "✓ Created $(ENV_FILE) from .env.example"; \
		echo "  → Fill in SUPABASE_SERVICE_ROLE_KEY, SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD"; \
		echo "  → Get the service role key from: supabase status (after starting)"; \
		echo "  → Then re-run: make setup-local"; \
		exit 0; \
	fi
	@echo "Starting Supabase..."
	supabase start
	@echo "Running migrations..."
	$(MAKE) db-migrate
	@echo ""
	@echo "✓ Local setup complete."
	@echo "  Admin user will be created on first 'make dev' if SEED_ADMIN_EMAIL is set."
	@echo "  Run: make dev"

## setup-prod: Production bootstrap guide
setup-prod:
	@echo "Production setup — run these steps in order:"
	@echo ""
	@echo "  1. Bootstrap GCP + Cloudflare + Supabase infrastructure:"
	@echo "       cd infra && bash scripts/bootstrap.sh"
	@echo ""
	@echo "  2. Set secrets in GitHub (CI/CD will auto-deploy on merge to main)."
	@echo ""
	@echo "  3. Set SEED_ADMIN_EMAIL + SEED_ADMIN_PASSWORD in Cloud Run env vars:"
	@echo "       gcloud run services update mbgc-api --region=us-central1 \\"
	@echo "         --set-env-vars SEED_ADMIN_EMAIL=you@example.com,SEED_ADMIN_PASSWORD=secret"
	@echo ""
	@echo "  4. The API creates the admin user on first boot. Remove the seed vars after."
	@echo ""
	@echo "  See SETUP.md for full details."

# ── Daily development ────────────────────────────────────────────────────────

## dev: Start API + web in tmux (attach with: tmux attach -t mbgc)
dev:
	@tmux kill-session -t mbgc 2>/dev/null || true
	@tmux new-session -d -s mbgc -n api "cd services/api && make dev 2>&1; read"
	@tmux new-window -t mbgc -n web "cd web && bun run dev 2>&1; read"
	@tmux select-window -t mbgc:api
	@echo "Services started in tmux. Attach with: tmux attach -t mbgc"

## db-migrate: Apply all pending migrations
db-migrate:
	$(MAKE) -C services/api migrate-up

## db-reset: Drop and recreate the local database (local only — irreversible)
db-reset:
	$(MAKE) -C services/api migrate-down
	$(MAKE) -C services/api migrate-up

# ── Build & test ─────────────────────────────────────────────────────────────

## build: Build API binary
build:
	$(MAKE) -C services/api build
	$(MAKE) -C web build

## test: Run all tests
test:
	$(MAKE) -C services/api test-v

## lint: Lint all code (Go + web + infra)
lint:
	$(MAKE) -C services/api lint
	$(MAKE) -C web lint
	cd infra && tflint --chdir=.

# ── Secret rotation ──────────────────────────────────────────────────────────

## rotate-secrets: Rotate secrets interactively (cloudflare | supabase | api | all)
rotate-secrets:
	sh infra/scripts/rotate-secrets.sh $(filter-out $@,$(MAKECMDGOALS))

# ── Acai spec-driven development ─────────────────────────────────────────────

## acai-push: Push specs + ACID refs to the dashboard
acai-push:
	npx @acai.sh/cli push --all

## acai-status: Show current feature status
acai-status:
	npx @acai.sh/cli features --json

## acai-features: List all features
acai-features:
	npx @acai.sh/cli features

# ── Help ─────────────────────────────────────────────────────────────────────

## help: Show this help
help:
	@grep -E '^## ' Makefile | sed 's/## //' | column -t -s ':'

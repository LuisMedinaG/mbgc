.PHONY: setup-local setup-infra bootstrap dev db-migrate db-reset test lint build \
        rotate-secrets acai-push acai-status acai-features help

# Root Makefile — mbgc monorepo
# Run `make help` to see all targets.

ENV_FILE := services/api/.env

# ── First-time setup ─────────────────────────────────────────────────────────

## setup-local: First-time local dev setup (copies .env, starts Supabase, migrates)
setup-local:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		cp services/api/.env.example $(ENV_FILE); \
		echo "✓ Created $(ENV_FILE) — DATABASE_URL and SUPABASE_URL are pre-filled for local."; \
		echo ""; \
		echo "  Fill in the three remaining values:"; \
		echo "    SUPABASE_SERVICE_ROLE_KEY  ← supabase status → Secret key"; \
		echo "    SEED_ADMIN_EMAIL           ← your admin email"; \
		echo "    SEED_ADMIN_PASSWORD        ← your admin password (min 6 chars)"; \
		echo ""; \
		echo "  If Supabase isn't running yet:  supabase start && supabase status"; \
		echo "  Then re-run:                    make setup-local"; \
		exit 0; \
	fi
	@echo "Starting Supabase..."
	supabase start
	@echo "Running migrations..."
	$(MAKE) db-migrate
	@echo ""
	@echo "✓ Local setup complete."
	@if grep -q '^SEED_ADMIN_EMAIL=.\+' $(ENV_FILE) 2>/dev/null; then \
		echo "  ✓ Admin user will be seeded on first 'make dev' (SEED_ADMIN_EMAIL is set)."; \
	else \
		echo "  ⚠ Set SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD in $(ENV_FILE) to seed an admin on first boot."; \
	fi
	@echo "  Run: make dev"

## setup-infra: First-time cloud infra setup (copies infra/.env, runs bootstrap)
setup-infra:
	@if [ ! -f infra/.env ]; then \
		cp infra/.env.example infra/.env; \
		echo "✓ Created infra/.env from infra/.env.example"; \
		echo "  Fill in your secrets, then re-run: make setup-infra"; \
		echo "  See SETUP.md → Cloud infra setup for a field-by-field guide."; \
		exit 0; \
	fi
	$(MAKE) bootstrap

## bootstrap: Run infra/scripts/bootstrap.sh (provisions GCP/CF/Supabase, syncs GitHub secrets)
bootstrap:
	bash infra/scripts/bootstrap.sh

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

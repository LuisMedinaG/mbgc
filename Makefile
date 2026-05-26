.PHONY: dev build test lint tidy dev-all db-setup db-check-env

# Root Makefile — mbgc monorepo

db-check-env:
	@env_file="services/api/.env"; \
	if [ ! -f "$$env_file" ]; then \
		echo "ERROR: $$env_file not found. Copy services/api/.env.example and set DATABASE_URL."; \
		exit 1; \
	fi; \
	if ! grep -q "DATABASE_URL" "$$env_file"; then \
		echo "ERROR: DATABASE_URL not set in $$env_file"; \
		exit 1; \
	fi
	@echo "✓ .env OK"

db-setup: db-check-env
	@echo "Starting local Supabase..."
	supabase start
	@echo "Running migrations..."
	$(MAKE) -C services/api migrate-up
	@echo "Done. Run 'supabase status' to see local URLs and keys."

dev-all:
	@tmux kill-session -t mbgc 2>/dev/null || true
	@tmux new-session -d -s mbgc -n api "cd services/api && make dev 2>&1; read"
	@tmux new-window -t mbgc -n web "cd web && bun run dev 2>&1; read"
	@tmux select-window -t mbgc:api
	@echo "Services started. Attach with: tmux attach -t mbgc"

.PHONY: dev build test lint tidy clean dev-all db-setup db-check-env

# Root Makefile — mbgc monorepo
SERVICES := gateway auth game importer monolith
DB_SERVICES := auth game importer

db-check-env:
	@for svc in $(DB_SERVICES); do \
		env_file="services/$$svc/.env"; \
		if [ ! -f "$$env_file" ]; then \
			echo "ERROR: $$env_file not found. Copy services/$$svc/.env.example and set DATABASE_URL."; \
			exit 1; \
		fi; \
		if ! grep -q "DATABASE_URL" "$$env_file"; then \
			echo "ERROR: DATABASE_URL not set in $$env_file"; \
			exit 1; \
		fi; \
	done
	@echo "✓ .env files OK"

db-setup: db-check-env
	@echo "Starting local Supabase..."
	supabase start
	@echo "Running migrations..."
	$(MAKE) -C services/auth migrate-up
	$(MAKE) -C services/game migrate-up
	$(MAKE) -C services/importer migrate-up
	@echo "Done. Run 'supabase status' to see local URLs and keys."

dev-all:
	@tmux kill-session -t mbgc 2>/dev/null || true
	@tmux new-session -d -s mbgc -n shared "echo 'mbgc dev session — ctrl+b d to detach' && exec zsh"
	@tmux new-window -t mbgc -n gateway "cd services/gateway && make dev 2>&1; read"
	@tmux new-window -t mbgc -n auth "cd services/auth && make dev 2>&1; read"
	@tmux new-window -t mbgc -n game "cd services/game && make dev 2>&1; read"
	@tmux new-window -t mbgc -n importer "cd services/importer && make dev 2>&1; read"
	@tmux new-window -t mbgc -n monolith "cd services/monolith && make dev 2>&1; read"
	@tmux new-window -t mbgc -n web "cd web && bun run dev 2>&1; read"
	@tmux select-window -t mbgc:shared
	@echo "All services started. Attach with: tmux attach -t mbgc"

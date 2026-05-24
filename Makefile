.PHONY: dev build test lint tidy clean dev-all

# Root Makefile — mbgc monorepo
SERVICES := gateway auth game importer monolith

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

.PHONY: dev build test lint tidy clean dev-all

# Root Makefile — mbgc monorepo
# Run `make dev-all` to start all services, or `make dev SERVICE=gateway` for one.

SERVICES := gateway auth game importer monolith

dev:
	@echo "Usage: make dev SERVICE=<service>"
	@echo "Available services: $(SERVICES)"
	@echo "Or run 'make dev-all' to start all services"

dev-all:
	@tmux kill-session -t mbgc 2>/dev/null || true
	@tmux new-session -d -s mbgc -n shared "cd pkg/shared && go mod tidy"
	@tmux new-window -t mbgc -n gateway "cd services/gateway && make dev"
	@tmux new-window -t mbgc -n auth "cd services/auth && make dev"
	@tmux new-window -t mbgc -n game "cd services/game && make dev"
	@tmux new-window -t mbgc -n importer "cd services/importer && make dev"
	@tmux new-window -t mbgc -n monolith "cd services/monolith && make dev"
	@tmux new-window -t mbgc -n web "cd web && bun run dev"
	@tmux select-window -t mbgc:shared
	@echo "All services started in tmux session 'mbgc'"
	@echo "Attach with: tmux attach -t mbgc"

build:
	@for dir in $(SERVICES); do \
		echo "Building services/$$dir..."; \
		(cd services/$$dir && make build) || exit 1; \
	done

test:
	@for dir in pkg/shared $(SERVICES); do \
		echo "Testing $$dir..."; \
		(cd $$dir && go test ./...) || exit 1; \
	done

test-v:
	@for dir in pkg/shared $(SERVICES); do \
		echo "Testing $$dir (verbose)..."; \
		(cd $$dir && go test -v -race ./...) || exit 1; \
	done

lint:
	@for dir in pkg/shared $(SERVICES); do \
		echo "Linting $$dir..."; \
		(cd $$dir && go vet ./...) || exit 1; \
	done

tidy:
	@for dir in pkg/shared $(SERVICES); do \
		echo "Tidying $$dir..."; \
		(cd $$dir && go mod tidy); \
	done

clean:
	@for dir in $(SERVICES); do \
		echo "Cleaning services/$$dir..."; \
		(cd services/$$dir && rm -f server); \
	done
	@rm -f coverage.html coverage.out

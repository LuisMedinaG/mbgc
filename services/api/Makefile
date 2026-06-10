.PHONY: dev build test test-v test-integration lint tidy migrate-up migrate-down
APP ?= server
PORT ?= 8080

dev:
	bash -c 'set -a; source .env 2>/dev/null; set +a; go run ./cmd/server'

build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o $(APP) ./cmd/server

test:
	go test ./...

test-v:
	go test -v -race ./...

## test-integration: Run the real-DB smoke tests (requires MBGC_TEST_DATABASE_URL)
test-integration:
	@if [ -z "$$MBGC_TEST_DATABASE_URL" ]; then \
		echo "MBGC_TEST_DATABASE_URL is not set — skipping integration tests."; \
		echo "  Set it to a Postgres URL to run the smoke tests against a real DB."; \
		echo "  Example: MBGC_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \\"; \
		echo "             make test-integration"; \
		exit 0; \
	fi
	go test -v -race ./internal/integration/...

lint:
	go vet ./...

tidy:
	go mod tidy

migrate-up:
	bash -c 'set -a; source .env 2>/dev/null; set +a; \
	  migrate -path migrations -database "$$DATABASE_URL" up'

migrate-down:
	bash -c 'set -a; source .env 2>/dev/null; set +a; \
	  migrate -path migrations -database "$$DATABASE_URL" down 1'

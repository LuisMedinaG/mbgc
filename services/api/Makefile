.PHONY: dev build test test-v lint tidy migrate-up migrate-down
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

.PHONY: dev build test lint tidy migrate-up migrate-down docker-build

APP ?= server
PORT ?= 8002

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
	bash -c 'set -a; source .env 2>/dev/null; set +a; psql "$$DATABASE_URL" -f migrations/001_init.up.sql'

migrate-down:
	bash -c 'set -a; source .env 2>/dev/null; set +a; psql "$$DATABASE_URL" -f migrations/001_init.down.sql'

docker-build:
	docker build -f deploy/Dockerfile -t mbgc-game-service .

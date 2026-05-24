.PHONY: dev build test lint tidy docker-build

APP ?= server
PORT ?= 8000

dev:
	go run ./cmd/server

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

docker-build:
	docker build -f deploy/Dockerfile -t mbgc-gateway .

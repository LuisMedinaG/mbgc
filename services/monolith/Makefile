.PHONY: build run dev dev-go clean \
        bgg-login test test-v cover cover-html vet check

GOCACHE ?= /tmp/go-build-cache
GOENV = env GOCACHE=$(GOCACHE)
GO = $(GOENV) go

# ── Go ───────────────────────────────────────────────────────────────

build:
	$(GO) build -o boardgames .

run: build
	./boardgames

dev:
	$(GO) run .

dev-go: dev

# ── Tests & quality ──────────────────────────────────────────────────

test:
	$(GO) test ./...

test-v:
	$(GO) test ./... -v

cover:
	$(GO) test ./... -cover

cover-html:
	$(GO) test ./... -coverprofile=/tmp/coverage.out && \
	$(GO) tool cover -html=/tmp/coverage.out -o /tmp/coverage.html && \
	echo "Coverage report: /tmp/coverage.html"

vet:
	$(GO) vet ./...

check: build test vet

# ── Maintenance ───────────────────────────────────────────────────────

clean:
	rm -f boardgames games.db

bgg-login:
	$(GO) run ./cmd/bgg-login

test-token:
	$(GO) run ./cmd/test-token

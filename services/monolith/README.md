# My Board Game Collection

A small Go web app for browsing your board games, opening rulebook links, and storing player-aid images.

**Stack:** Go · `html/template` · SQLite · HTMX · Tailwind CSS v4

## What It Does

- Multi-user accounts with per-user game collections
- Filter games by category, player count, play time, weight, rating, and language
- Store rulebook links and upload player-aid files
- Tag games with custom "vibes" for mood-based browsing
- Sync owned games from BoardGameGeek (BGG)
- JSON REST API (`/api/v1/`) with JWT auth alongside the HTMX frontend

## Prerequisites

- Go 1.25 or newer
- No C compiler required
- [Tailwind CSS CLI](https://tailwindcss.com) — only needed when editing CSS or templates

```sh
# First-time setup: download the Tailwind standalone CLI (macOS Apple Silicon)
make tailwind-install
```

The compiled CSS (`static/style.css`) is committed to the repo, so you can build and run the app without Tailwind installed. Only run `make tailwind-install` when you need to edit CSS or add new Tailwind classes.

## Quick Start

```sh
make run
```

Then open `http://localhost:8080`.

On first run the app creates `games.db`, creates `data/uploads/`, and seeds a few sample games if the database is empty.

## Development

```sh
# Recommended: runs Go + Tailwind watcher together (Ctrl-C stops both)
make dev

# Go only (when you're not editing CSS)
make dev-go
```

## Commands

| Command | Description |
|---------|-------------|
| `make dev` | Run Go app + Tailwind CSS watcher (recommended) |
| `make dev-go` | Run Go app only (CSS must be pre-built) |
| `make css` | Build CSS once, minified (run before committing) |
| `make css-watch` | Watch CSS for changes |
| `make run` | Build CSS + binary, then run |
| `make build` | Build the `boardgames` binary |
| `make test` | Run all tests |
| `make test-v` | Run tests with verbose output |
| `make cover` | Run tests with coverage report |
| `make cover-html` | Generate HTML coverage report |
| `make check` | CSS + build + test + vet |
| `make clean` | Remove binary, local database, Tailwind CLI |
| `make tailwind-install` | Download Tailwind CLI (first-time setup) |

## CSS Architecture

CSS is managed with **Tailwind CSS v4** (standalone CLI — no Node.js required).

- **Edit**: `static/input.css` — Tailwind source with `@theme` tokens and legacy CSS imports
- **Output**: `static/style.css` — compiled by Tailwind, committed to repo, embedded in binary
- **Theme**: brand colors, radius, and shadows defined in `@theme {}` in `input.css`

Never edit `static/style.css` directly — it's overwritten on every build.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP server port |
| `DB_PATH` | `games.db` | SQLite database path |
| `DATA_DIR` | `data` | Directory for uploads and images |
| `SESSION_SECRET` | insecure default | Secret for sessions and JWT signing — set in production |
| `BGG_TOKEN` | unset | Enables BoardGameGeek import (server-side only) |
| `BGG_COOKIE` | unset | Fallback BGG auth if `BGG_TOKEN` is not set |

Example:

```sh
PORT=3000 DB_PATH=./data/collection.db SESSION_SECRET=your-secret make run
```

Create accounts via `/signup`. For local development, keep secrets in a `.env` file (not committed).

## Fly.io Deployment

Use Fly secrets for sensitive values:

```sh
fly secrets set \
  SESSION_SECRET='your-long-random-secret' \
  BGG_TOKEN=your_bgg_token
```

Recommended:

- Mount a persistent Fly volume for the SQLite database and uploads directory.
- Set `DB_PATH` to your mounted volume, for example `/data/games.db`.
- Keep `BGG_TOKEN` server-side only. Never expose it in HTML, JavaScript, or browser storage.
- Run the app behind Fly's HTTPS endpoint; this app sends HSTS when served over HTTPS.

## Project Structure

```text
.
├── main.go              # Server setup, routes, middleware
├── internal/
│   ├── handler/         # HTTP handlers (HTMX + JSON API)
│   ├── store/           # SQLite data access layer
│   ├── httpx/           # Middleware (auth, CSRF, rate-limit, JWT)
│   ├── bgg/             # BGG API client
│   ├── render/          # Template renderer
│   ├── model/           # Domain structs
│   ├── viewmodel/       # View-layer data for templates
│   └── filter/          # Game filtering logic
├── templates/           # Embedded HTML templates
├── static/
│   ├── input.css        # Tailwind source (edit this)
│   ├── style.css        # Compiled CSS (generated — do not edit)
│   └── styles/          # Legacy CSS (removed during Tailwind migration)
├── data/uploads/        # Uploaded player-aid files
└── Makefile
```

## Routes

The app serves two interfaces from the same server:

- **HTMX frontend** — server-rendered HTML at `/`, `/games`, `/vibes`, `/import`, etc.
- **JSON REST API** — under `/api/v1/` with JWT auth (`Authorization: Bearer`)

See `agent_docs/ARCHITECTURE-REF.md` for the full route table.

## Storage

- Templates and static assets are embedded in the Go binary with `go:embed`.
- SQLite data lives in `games.db` by default.
- Uploaded player-aid files are stored in `data/uploads/`.
- Uploaded files are validated as images before being saved.

## Testing

```sh
make test           # Run all tests
make test-v         # Verbose output
make cover          # Coverage report
make cover-html     # HTML coverage report → /tmp/coverage.html
```

## Maintenance

Reset the local database:

```sh
rm -f games.db games.db-shm games.db-wal
```

Remove uploaded files:

```sh
rm -rf data/uploads
```

Update dependencies:

```sh
go get -u ./...
go mod tidy
```

Build for deployment:

```sh
make build
PORT=8080 DB_PATH=/var/data/games.db ./boardgames
```

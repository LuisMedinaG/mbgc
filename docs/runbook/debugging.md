# Debugging Go in VSCode

## Setup

### 1. Install VSCode Go Extension

Install the [Go extension](https://marketplace.visualstudio.com/items?itemName=golang.go) by Go Team at Google.

### 2. Launch Config

Create `.vscode/launch.json` in `services/api/`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug API",
      "type": "go",
      "request": "launch",
      "mode": "debug",
      "program": "${workspaceFolder}/cmd/server",
      "env": {
        "ENV": "local",
        "LOG_LEVEL": "debug"
      },
      "envFile": "${workspaceFolder}/.env",
      "preLaunchTask": "database:migrate-and-seed",
      "serverReadyAction": {
        "pattern": "Starting server on port (\\d+)",
        "uriFilter": "https?://localhost:(\\d+)",
        "action": "openExternally"
      }
    },
    {
      "name": "Debug API (no migrate)",
      "type": "go",
      "request": "launch",
      "mode": "debug",
      "program": "${workspaceFolder}/cmd/server",
      "env": {
        "ENV": "local",
        "LOG_LEVEL": "debug"
      },
      "envFile": "${workspaceFolder}/.env"
    }
  ]
}
```

### 3. Tasks for pre-launch

Create `.vscode/tasks.json` in `services/api/`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "database:migrate-and-seed",
      "type": "shell",
      "command": "cd ${workspaceFolder}/../.. && make db-migrate",
      "problemMatcher": []
    },
    {
      "label": "supabase:start",
      "type": "shell",
      "command": "supabase start",
      "problemMatcher": []
    }
  ]
}
```

## Debugging Workflow

### Starting the environment

```sh
# Terminal 1: Start Supabase
supabase start

# Terminal 2: Run migrations + seed
make db-migrate
```

### Attaching debugger

1. Set breakpoints in your code
2. Press `F5` or use the Debug panel
3. Select "Debug API" configuration
4. Make HTTP requests to trigger breakpoints

### Debugging with dlv directly

```sh
# Attach to running process
dlv attach $(pgrep -f "go run ./cmd/server")

# Headless debug server
dlv debug ./cmd/server --listen=127.0.0.1:2345
```

## Common Scenarios

### Breakpoint on HTTP handler

```go
// services/api/internal/game/handler.go
func (h *Handler) ListGames(w http.ResponseWriter, r *http.Request) {
    // Set breakpoint here
    ctx := r.Context()
    // ...
}
```

### Breakpoint on store layer

```go
// services/api/internal/game/store.go
func (s *Store) ListGames(ctx context.Context, userID uuid.UUID, filter game.ListFilter) ([]game.Game, int, error) {
    // Set breakpoint here to see SQL queries
    // ...
}
```

### Debugging JWT validation

```go
// services/api/internal/jwt/verifier.go
func (v *Verifier) Verify(...) (*Claims, error) {
    // Set breakpoint here to inspect tokens
}
```

### Debugging BGG importer

```go
// services/api/internal/importer/thing_parser.go
func ParseThing(xmlReader io.Reader) (*ThingResponse, error) {
    // Set breakpoint here to inspect BGG XML parsing
}
```

## Tips

- **Hot reload**: Use `delve` or set `dlv` as the debugger for live reloading
- **Environment**: Ensure `.env` is loaded (see `go run ./cmd/server` vs `make dev`)
- **Race conditions**: Use "Debug API" with race detector enabled via `go test -race`
- **Logs**: Check `slog` output in Debug Console for structured logs
- **Remote debug**: For Cloud Run, use [cloud-debug-go](https://cloud.google.com/blog/products/devops-sre/analyzing-go-programs-with-cloud-debugger)

## VSCode Extensions

| Extension | Purpose |
|-----------|---------|
| [Go](https://marketplace.visualstudio.com/items?itemName=golang.go) | Core debugging, IntelliSense |
| [Snoop](https://marketplace.visualstudio.com/items?itemName=k--kato.snoop) | Variable inspection |
| [Go Test Explorer](https://marketplace.visualstudio.com/items?itemName=prezmik.vscode-go-test-explorer) | Run/debug tests |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Breakpoints not hit | Ensure `dlv` is installed: `go install github.com/go-delve/delve/cmd/dlv@latest` |
| "Cannot find process" | Check `.env` is loading correctly; verify `ENV=local` |
| Debug console empty | Set `LOG_LEVEL=debug` in launch config |
| Slow stepping | Disable source maps optimization in VSCode settings |
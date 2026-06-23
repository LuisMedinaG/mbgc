# Debugging Go in VSCode

## Setup

### 1. Install VSCode Go Extension

Install the [Go extension](https://marketplace.visualstudio.com/items?itemName=golang.go) by Go Team at Google.

### 2. Launch Config

The `.vscode/` folder is at the project root (`/Users/lumedina/Documents/Projects/mbgc/.vscode/`).

**`.vscode/launch.json`**:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug API",
            "type": "go",
            "request": "launch",
            "mode": "debug",
            "cwd": "${workspaceFolder}/services/api",
            "program": "${workspaceFolder}/services/api/cmd/server",
            "env": {
                "ENV": "local",
                "LOG_LEVEL": "debug"
            },
            "envFile": "${workspaceFolder}/services/api/.env",
            "preLaunchTask": "database:migrate-and-seed"
        },
        {
            "name": "Debug API (no migrate)",
            "type": "go",
            "request": "launch",
            "mode": "debug",
            "cwd": "${workspaceFolder}/services/api",
            "program": "${workspaceFolder}/services/api/cmd/server",
            "env": {
                "ENV": "local",
                "LOG_LEVEL": "debug"
            },
            "envFile": "${workspaceFolder}/services/api/.env"
        }
    ]
}
```

**`.vscode/tasks.json`**:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "supabase:start",
            "type": "shell",
            "command": "supabase start",
            "problemMatcher": []
        },
        {
            "label": "database:migrate-and-seed",
            "type": "shell",
            "command": "make db-migrate",
            "problemMatcher": [],
            "dependsOrder": "sequence",
            "dependsOn": ["supabase:start"]
        }
    ]
}
```

## Debugging Workflow

### Starting the environment

```sh
# Terminal 1: Start Supabase (first time only, or if stopped)
supabase start

# Run migrations + seed
make db-migrate
```

### Using VSCode debugger

1. Set breakpoints in your code
2. Press `F5` or use the Debug panel
3. Select "Debug API" configuration
4. Make HTTP requests to trigger breakpoints

### Debugging with dlv directly

**Headless debug server** (run from `services/api/`):

```sh
cd services/api
dlv debug ./cmd/server --listen=127.0.0.1:2345
```

Then in VSCode, use a "Attach to Process" configuration:

```json
{
    "name": "Attach to dlv",
    "type": "go",
    "request": "attach",
    "mode": "remote",
    "remoteStackTracePath": "",
    "showGlobalVariables": true,
    "host": "127.0.0.1",
    "port": 2345
}
```

**Attach to running process**:

First find the PID:

```sh
pgrep -a -f "services/api"
```

Then attach:

```sh
cd services/api
dlv attach <PID>
```

## Common Scenarios

### Breakpoint on HTTP handler

```go
// services/api/internal/catalog/handler.go
func (h *Handler) ListGames(w http.ResponseWriter, r *http.Request) {
    // Set breakpoint here
    ctx := r.Context()
    // ...
}
```

### Breakpoint on store layer

```go
// services/api/internal/catalog/store.go
func (s *Store) ListGames(ctx context.Context, userID uuid.UUID, filter catalog.ListFilter) ([]catalog.Game, int, error) {
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
- **Race conditions**: Use race detector via `go test -race`
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
| `dlv debug` "directory not found" | Must `cd services/api` first — `cmd/server` is relative to that dir |
| `dlv attach` "you must provide a PID" | Use `pgrep -a -f "services/api"` to find PID; process must be running |
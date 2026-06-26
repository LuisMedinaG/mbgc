# Codex stale node_repl MCP server

## Symptoms
- `codex doctor`: `node_repl stdio command ".../AppTranslocation/.../Codex.app/.../node_repl" is not resolvable`
- `codex mcp list` shows `node_repl` enabled with an AppTranslocation path.

## Root cause
Codex config kept a temporary macOS AppTranslocation path after the app bundle moved or expired.

## Fix
```sh
codex mcp remove node_repl
codex doctor
```

## Prevention
Do not keep MCP commands that point into `/private/var/.../AppTranslocation/`.

## Related
- `~/.codex/config.toml` — Codex MCP server config

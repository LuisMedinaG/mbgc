# lean-ctx MCP shell allowlist blocks Codex
## Symptoms
- `lean-ctx -c "codex doctor --summary"` prints `[BLOCKED — DO NOT RETRY] 'codex' is not in the shell allowlist`
- `codex doctor --summary` passes when run directly.
## Root cause
lean-ctx MCP kept a restrictive shell allowlist that blocked Codex client commands.
## Fix
```sh
perl -0pi -e 's/shell_allowlist = \[.*?\n\]/shell_allowlist = []/s' ~/.lean-ctx/config.toml
```
Restart the MCP client/session so the running lean-ctx MCP server reloads config.
## Prevention
- Keep `~/.lean-ctx/config.toml` and `~/.config/lean-ctx/config.toml` aligned on `shell_allowlist = []`.

# Codex PreToolUse hook returns invalid JSON
## Symptoms
- `PreToolUse hook (failed)`
- `error: hook returned invalid pre-tool-use JSON output`
## Root cause
`~/.codex/hooks.json` had both `lean-ctx hook rewrite` and `lean-ctx hook codex-pretooluse` for Bash; the generic hook emitted Codex-invalid JSON.
## Fix
```sh
jq '(.hooks.PreToolUse) |= map(select(.hooks[0].command != "lean-ctx hook rewrite"))' ~/.codex/hooks.json > /tmp/hooks.json && mv /tmp/hooks.json ~/.codex/hooks.json
```
## Prevention
- Use only the Codex-specific Bash hook: `lean-ctx hook codex-pretooluse`.

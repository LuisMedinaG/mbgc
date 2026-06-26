# Codex invalid Stop hook JSON

## Symptoms
- `Stop hook (failed)`
- `error: hook returned invalid stop hook JSON output`

## Root cause
The Stop hook wrote output that Codex tried to parse as Stop-hook JSON.

## Fix
```sh
jq '(.hooks.Stop[0].hooks[0].command) = "lean-ctx hook observe >/dev/null 2>&1 || true"' ~/.codex/hooks.json > /tmp/hooks.json
mv /tmp/hooks.json ~/.codex/hooks.json
```

## Prevention
Keep Stop hooks silent unless they emit valid Stop-hook JSON.

## Related
- `~/.codex/hooks.json` — Codex hook config

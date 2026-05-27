# Supabase Link Fails with Unauthorized

## Symptoms

```
supabase link --project-ref mlltpfszhtxhphoaeydh
Unexpected error retrieving remote project status: {"message":"Unauthorized"}
```

## Root Cause

The `supabase link` command was run from the wrong directory. The Supabase CLI looks for `.supabase/config.toml` (or `supabase/config.toml`) in the current working directory. When run from the project root without the config present, it fails to authenticate properly against the remote project.

## Fix

Run the command from the `supabase/` subdirectory or use `--workdir`:

```sh
supabase link --project-ref mlltpfszhtxhphoaeydh --workdir ./supabase
```

Or cd into the directory first:

```sh
cd supabase
supabase link --project-ref mlltpfszhtxhphoaeydh
```

## Prevention

Always run Supabase CLI commands from the `supabase/` directory or use `--workdir ./supabase`.

## Related

- `supabase/config.toml` — project configuration
- `AGENTS.md` — Supabase local vs remote workflow

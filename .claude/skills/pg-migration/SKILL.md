---
name: pg-migration
description: Add a Postgres schema migration to a microservice. Use when asked to add a table, add a column, or alter the database schema in any of the Go microservices (auth, game, importer).
---

# Postgres Migration

Each service owns its own schema and migration files. Migrations run via `golang-migrate` at startup.

## File location & naming

```
services/<name>/migrations/
  NNN_description.up.sql    # forward migration
  NNN_description.down.sql  # rollback
```

Use sequential numbers: `001`, `002`, `003`, … Match the existing sequence in the service.

## Conventions

- Each service uses a named schema: `auth.`, `games.`, `importer.`
- PKs: `bigserial PRIMARY KEY`
- User references: `user_id uuid NOT NULL` — no FK to `auth.users` (Supabase manages that table)
- Timestamps: `timestamptz NOT NULL DEFAULT now()`
- Arrays: `text[] NOT NULL DEFAULT '{}'`, `int[] NOT NULL DEFAULT '{}'`
- Add `updated_at` trigger when rows are mutable (copy pattern from `games.set_updated_at`)
- FTS: `tsvector GENERATED ALWAYS AS (...) STORED` + GIN index

## New table template

```sql
CREATE TABLE IF NOT EXISTS <schema>.<table> (
    id         bigserial    PRIMARY KEY,
    user_id    uuid         NOT NULL,
    name       text         NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NOT NULL DEFAULT now(),
    UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS <table>_user_id_idx ON <schema>.<table> (user_id);

COMMENT ON COLUMN <schema>.<table>.user_id IS
    'Supabase Auth user UUID. No FK — Supabase manages auth.users.';
```

Down migration:
```sql
DROP TABLE IF EXISTS <schema>.<table>;
```

## New column on existing table

```sql
-- up
ALTER TABLE <schema>.<table> ADD COLUMN IF NOT EXISTS <col> <type> NOT NULL DEFAULT <val>;

-- down
ALTER TABLE <schema>.<table> DROP COLUMN IF EXISTS <col>;
```

## After writing the SQL

1. Update the store's column list / scan function in `internal/store/store.go`
2. Update the model struct in `internal/model/`
3. Update the API converter (model → response struct)
4. Run migrations: `make migrate-up` from the service directory
5. Verify with `supabase status` → connect and `SELECT * FROM <schema>.<table> LIMIT 1`

## Commands

```sh
cd services/<name>
make migrate-up      # apply pending migrations
make migrate-down    # roll back one step
```

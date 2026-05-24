CREATE SCHEMA IF NOT EXISTS importer;

-- Rate limit: one row per user, reset daily
CREATE TABLE IF NOT EXISTS importer.rate_limits (
    user_id    uuid    PRIMARY KEY,
    count      int     NOT NULL DEFAULT 0,
    reset_date date    NOT NULL DEFAULT current_date
);

COMMENT ON TABLE importer.rate_limits IS
    'Tracks daily BGG sync usage per user. Reset automatically when reset_date < today.';

-- Audit log of every sync
CREATE TABLE IF NOT EXISTS importer.sync_log (
    id              bigserial   PRIMARY KEY,
    user_id         uuid        NOT NULL,
    games_imported  int         NOT NULL DEFAULT 0,
    full_refresh    boolean     NOT NULL DEFAULT false,
    synced_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sync_log_user_id_idx ON importer.sync_log (user_id);

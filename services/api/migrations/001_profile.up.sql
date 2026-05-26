-- Auth service manages application-level profile data.
-- Supabase Auth owns the auth.users table (email, password, sessions).
-- We store app-specific fields in the profile schema.

CREATE SCHEMA IF NOT EXISTS profile;

CREATE TABLE IF NOT EXISTS profile.users (
    id           uuid        PRIMARY KEY,
    bgg_username text,
    is_admin     boolean     NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE profile.users IS
    'Application profile data. id is the Supabase Auth user UUID.';

COMMENT ON COLUMN profile.users.id IS
    'Supabase Auth user UUID (auth.users.id). No FK constraint — Supabase manages that table.';

-- Auto-update updated_at on row changes
CREATE OR REPLACE FUNCTION profile.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER users_set_updated_at
    BEFORE UPDATE ON profile.users
    FOR EACH ROW
    EXECUTE FUNCTION profile.set_updated_at();

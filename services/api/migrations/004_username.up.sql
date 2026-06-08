-- Add an application-level username for login (alternative to email).
-- The JWT username claim continues to come from Supabase user_metadata;
-- this column exists solely for fast username -> email resolution at login.

ALTER TABLE profile.users ADD COLUMN IF NOT EXISTS username text;

-- Case-insensitive uniqueness; NULLs allowed (most users log in by email).
CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_idx
    ON profile.users (lower(username))
    WHERE username IS NOT NULL;

COMMENT ON COLUMN profile.users.username IS
    'Optional login handle. Resolved to the Supabase auth.users.email at login.';

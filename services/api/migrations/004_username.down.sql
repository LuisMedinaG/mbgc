DROP INDEX IF EXISTS profile.users_username_lower_idx;
ALTER TABLE profile.users DROP COLUMN IF EXISTS username;

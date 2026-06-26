-- Add user tier (basic / pro) to control BGG sync rate limits.
-- is_admin remains the superuser gate; tier governs window + quota for regular users.
ALTER TABLE profile.users
    ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'basic';

ALTER TABLE profile.users
    ADD CONSTRAINT users_tier_check CHECK (tier IN ('basic', 'pro'));

-- Migrate rate_limits from a daily-reset date to an absolute window-end timestamp.
-- reset_at means "this window expires at this time" — now() >= reset_at → new window.
-- Existing rows inherit a window that expires at the start of tomorrow UTC.
ALTER TABLE importer.rate_limits
    RENAME COLUMN reset_date TO reset_at;

ALTER TABLE importer.rate_limits
    ALTER COLUMN reset_at TYPE timestamptz
    USING (reset_at::timestamptz + interval '1 day');

COMMENT ON COLUMN importer.rate_limits.reset_at IS
    'Absolute UTC timestamp when the current rate-limit window expires. now() >= reset_at resets the counter.';

ALTER TABLE importer.rate_limits
    ALTER COLUMN reset_at TYPE date
    USING reset_at::date;

ALTER TABLE importer.rate_limits
    RENAME COLUMN reset_at TO reset_date;

ALTER TABLE profile.users DROP CONSTRAINT IF EXISTS users_tier_check;
ALTER TABLE profile.users DROP COLUMN IF EXISTS tier;

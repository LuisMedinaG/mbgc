-- Create admin user profile in production Supabase
-- Steps:
-- 1. Go to https://app.supabase.com → your project → Authentication → Users
-- 2. Create user with your email/password
-- 3. Copy the user UUID
-- 4. Replace 'YOUR_USER_UUID_HERE' below
-- 5. Go to SQL Editor → New query → paste this → RUN

INSERT INTO profile.users (id, is_admin)
VALUES ('YOUR_USER_UUID_HERE', true);

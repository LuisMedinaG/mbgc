#!/bin/bash
# Create admin user in Supabase (both local and prod)
# Usage: ./scripts/create-admin-user.sh <email> <password> [prod|local]

set -eu

EMAIL="${1:-}"
PASSWORD="${2:-}"
ENV="${3:-local}"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Usage: $0 <email> <password> [prod|local]"
  echo ""
  echo "Examples:"
  echo "  $0 admin@example.com mypassword local    # Local Supabase"
  echo "  $0 admin@example.com mypassword prod     # Production Supabase"
  exit 1
fi

if [ "$ENV" = "local" ]; then
  echo "📝 Creating admin user in LOCAL Supabase..."
  echo ""
  echo "1. Open Supabase Studio: http://127.0.0.1:54323"
  echo "2. Go to Authentication → Users"
  echo "3. Click 'Create user'"
  echo "4. Enter:"
  echo "   Email: $EMAIL"
  echo "   Password: $PASSWORD"
  echo "5. Click Create"
  echo ""
  echo "6. Copy the user UUID from the users list"
  echo ""
  echo "7. Run this command with the UUID:"
  echo "   psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c \\"
  echo "     \"INSERT INTO profile.users (id, is_admin) VALUES ('<UUID>', true)\""
  echo ""

elif [ "$ENV" = "prod" ]; then
  echo "📝 Creating admin user in PRODUCTION Supabase..."
  echo ""
  echo "1. Go to https://app.supabase.com → Your Project"
  echo "2. Click 'Authentication' → 'Users'"
  echo "3. Click 'Create user'"
  echo "4. Enter:"
  echo "   Email: $EMAIL"
  echo "   Password: $PASSWORD"
  echo "5. Click Create"
  echo ""
  echo "6. Copy the user UUID from the users list"
  echo ""
  echo "7. Go to 'SQL Editor' → 'New query'"
  echo "8. Paste and run this SQL with the UUID:"
  echo "   INSERT INTO profile.users (id, is_admin) VALUES ('<UUID>', true);"
  echo ""
  echo "9. Press 'RUN'"
  echo ""
else
  echo "❌ Unknown environment: $ENV"
  echo "Use 'local' or 'prod'"
  exit 1
fi

echo "✅ Once done, you can login with:"
echo "   Email: $EMAIL"
echo "   Password: $PASSWORD"

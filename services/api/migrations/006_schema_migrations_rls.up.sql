-- golang-migrate's bookkeeping table is never queried via PostgREST;
-- revoke client-role grants instead of maintaining unused RLS policies.
-- Guard: anon/authenticated roles only exist on Supabase-backed Postgres.
DO $$
BEGIN
  REVOKE ALL ON public.schema_migrations FROM anon, authenticated;
EXCEPTION WHEN undefined_object THEN NULL;
END
$$;

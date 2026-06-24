-- golang-migrate's bookkeeping table is never queried via PostgREST;
-- revoke client-role grants instead of maintaining unused RLS policies.
REVOKE ALL ON public.schema_migrations FROM anon, authenticated;

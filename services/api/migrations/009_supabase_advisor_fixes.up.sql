ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deny_all ON public.schema_migrations;

DO $$
BEGIN
    CREATE POLICY deny_all ON public.schema_migrations
        FOR ALL
        TO anon, authenticated
        USING (false)
        WITH CHECK (false);
EXCEPTION WHEN undefined_object THEN
    NULL;
END
$$;

ALTER FUNCTION games.set_updated_at() SET search_path = pg_catalog, public;
ALTER FUNCTION profile.set_updated_at() SET search_path = pg_catalog, public;

DROP INDEX IF EXISTS games.idx_player_aids_game_id;
CREATE INDEX IF NOT EXISTS player_aids_game_id_idx ON games.player_aids (game_id);

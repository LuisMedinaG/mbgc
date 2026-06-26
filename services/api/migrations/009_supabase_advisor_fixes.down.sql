DO $$
BEGIN
    IF to_regclass('games.player_aids_game_id_idx') IS NOT NULL
        AND to_regclass('games.idx_player_aids_game_id') IS NULL THEN
        ALTER INDEX games.player_aids_game_id_idx RENAME TO idx_player_aids_game_id;
    END IF;
END
$$;

ALTER FUNCTION profile.set_updated_at() RESET search_path;
ALTER FUNCTION games.set_updated_at() RESET search_path;

DROP POLICY IF EXISTS deny_all ON public.schema_migrations;
ALTER TABLE public.schema_migrations DISABLE ROW LEVEL SECURITY;

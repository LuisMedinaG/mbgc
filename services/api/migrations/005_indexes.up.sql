-- ref: api-layer.PERF.1 — composite index for user-scoped game lists sorted by name
CREATE INDEX IF NOT EXISTS games_user_id_name_idx ON games.games (user_id, name);

-- ref: api-layer.PERF.2 — reverse lookup: which collections contain this game
-- PK on collection_games is (collection_id, game_id); game_id alone has no index.
CREATE INDEX IF NOT EXISTS collection_games_game_id_idx ON games.collection_games (game_id);

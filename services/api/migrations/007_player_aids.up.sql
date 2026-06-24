-- Create player_aids table for storing user-uploaded player aids (rule summaries, reference cards, etc.)
CREATE TABLE games.player_aids (
    id BIGSERIAL PRIMARY KEY,
    game_id BIGINT NOT NULL REFERENCES games.games(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    label TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for efficient lookups by game_id
CREATE INDEX idx_player_aids_game_id ON games.player_aids(game_id);

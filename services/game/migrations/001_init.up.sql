CREATE SCHEMA IF NOT EXISTS games;

-- Core games table with Postgres full-text search via generated tsvector column
CREATE TABLE IF NOT EXISTS games.games (
    id                   bigserial   PRIMARY KEY,
    user_id              uuid        NOT NULL,
    bgg_id               int,
    name                 text        NOT NULL,
    description          text,
    year_published       int,
    image                text,
    thumbnail            text,
    min_players          int,
    max_players          int,
    playtime             int,
    categories           text[]      NOT NULL DEFAULT '{}',
    mechanics            text[]      NOT NULL DEFAULT '{}',
    types                text[]      NOT NULL DEFAULT '{}',
    weight               numeric(4,2),
    rating               numeric(4,2),
    language_dependence  int,
    recommended_players  int[]       NOT NULL DEFAULT '{}',
    rules_url            text,
    -- Postgres FTS: replaces SQLite FTS5
    search_vector        tsvector    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(name, '') || ' ' || coalesce(description, '')
        )
    ) STORED,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, bgg_id)
);

CREATE INDEX IF NOT EXISTS games_user_id_idx        ON games.games (user_id);
CREATE INDEX IF NOT EXISTS games_bgg_id_idx         ON games.games (bgg_id);
CREATE INDEX IF NOT EXISTS games_search_vector_idx  ON games.games USING gin (search_vector);

COMMENT ON COLUMN games.games.user_id IS
    'Supabase Auth user UUID. No FK — Supabase manages auth.users.';

-- User-defined game groups (previously called "vibes")
CREATE TABLE IF NOT EXISTS games.collections (
    id          bigserial   PRIMARY KEY,
    user_id     uuid        NOT NULL,
    name        text        NOT NULL,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS collections_user_id_idx ON games.collections (user_id);

-- Many-to-many: games ↔ collections
CREATE TABLE IF NOT EXISTS games.collection_games (
    collection_id bigint NOT NULL REFERENCES games.collections (id) ON DELETE CASCADE,
    game_id       bigint NOT NULL REFERENCES games.games (id) ON DELETE CASCADE,
    PRIMARY KEY (collection_id, game_id)
);

-- Player aid images uploaded per game
CREATE TABLE IF NOT EXISTS games.player_aids (
    id         bigserial   PRIMARY KEY,
    game_id    bigint      NOT NULL REFERENCES games.games (id) ON DELETE CASCADE,
    filename   text        NOT NULL,
    label      text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION games.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER games_set_updated_at
    BEFORE UPDATE ON games.games
    FOR EACH ROW EXECUTE FUNCTION games.set_updated_at();

CREATE OR REPLACE TRIGGER collections_set_updated_at
    BEFORE UPDATE ON games.collections
    FOR EACH ROW EXECUTE FUNCTION games.set_updated_at();

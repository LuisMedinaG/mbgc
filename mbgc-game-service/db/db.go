package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

func New(connStr string) (*pgx.Conn, error) {
	conn, err := pgx.Connect(context.Background(), connStr)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if err := migrate(conn); err != nil {
		conn.Close(context.Background())
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return conn, nil
}

func migrate(conn *pgx.Conn) error {
	_, err := conn.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS games (
			id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			bgg_id         INTEGER UNIQUE,
			title          TEXT NOT NULL,
			year_published INTEGER,
			min_players    INTEGER,
			max_players    INTEGER,
			weight         NUMERIC(3,2),
			image_url      TEXT,
			description    TEXT,
			created_at     TIMESTAMPTZ DEFAULT now(),
			updated_at     TIMESTAMPTZ DEFAULT now()
		);

		CREATE TABLE IF NOT EXISTS collection_entries (
			id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			user_id    TEXT NOT NULL,
			game_id    UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
			status     TEXT NOT NULL CHECK (status IN ('owned','wishlist','played','for_trade')),
			rating     INTEGER CHECK (rating >= 1 AND rating <= 10),
			notes      TEXT,
			created_at TIMESTAMPTZ DEFAULT now(),
			updated_at TIMESTAMPTZ DEFAULT now(),
			UNIQUE(user_id, game_id)
		);

		CREATE TABLE IF NOT EXISTS player_aids (
			id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			game_id      UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
			uploaded_by  TEXT NOT NULL,
			filename     TEXT NOT NULL,
			content_type TEXT NOT NULL,
			size_bytes   BIGINT NOT NULL,
			data         BYTEA NOT NULL,
			created_at   TIMESTAMPTZ DEFAULT now()
		);
	`)
	return err
}

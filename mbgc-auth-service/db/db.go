package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Connect(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("pgxpool.New: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("db ping: %w", err)
	}

	if err := migrate(ctx, pool); err != nil {
		return nil, fmt.Errorf("migrate: %w", err)
	}

	return pool, nil
}

func migrate(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS profiles (
			user_id        TEXT PRIMARY KEY,
			email          TEXT NOT NULL,
			bgg_username   TEXT,
			role           TEXT NOT NULL DEFAULT 'user',
			import_quota   INTEGER NOT NULL DEFAULT 10,
			imports_used   INTEGER NOT NULL DEFAULT 0,
			created_at     TIMESTAMPTZ DEFAULT now(),
			updated_at     TIMESTAMPTZ DEFAULT now()
		)
	`)
	return err
}

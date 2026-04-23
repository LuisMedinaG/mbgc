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
		CREATE TABLE IF NOT EXISTS import_jobs (
			id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			user_id          TEXT NOT NULL,
			type             TEXT NOT NULL CHECK (type IN ('bgg', 'csv')),
			status           TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','done','failed')),
			total_items      INTEGER,
			processed_items  INTEGER NOT NULL DEFAULT 0,
			error_message    TEXT,
			created_at       TIMESTAMPTZ DEFAULT now(),
			updated_at       TIMESTAMPTZ DEFAULT now()
		)
	`)
	return err
}

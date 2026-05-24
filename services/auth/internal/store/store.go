package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/services/auth/internal/model"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

type Store struct {
	db *pgxpool.Pool
}

func New(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) GetProfile(ctx context.Context, userID string) (*model.Profile, error) {
	var p model.Profile
	err := s.db.QueryRow(ctx,
		`SELECT id, bgg_username, is_admin, created_at, updated_at
		 FROM profile.users WHERE id = $1`, userID).
		Scan(&p.ID, &p.BGGUsername, &p.IsAdmin, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, apierr.ErrNotFound
		}
		return nil, err
	}
	return &p, nil
}

// UpsertProfile creates or updates the profile row for a user.
// Called lazily on first GET /profile — no separate signup step needed.
func (s *Store) UpsertProfile(ctx context.Context, userID string) (*model.Profile, error) {
	var p model.Profile
	err := s.db.QueryRow(ctx,
		`INSERT INTO profile.users (id)
		 VALUES ($1)
		 ON CONFLICT (id) DO UPDATE SET updated_at = now()
		 RETURNING id, bgg_username, is_admin, created_at, updated_at`,
		userID).
		Scan(&p.ID, &p.BGGUsername, &p.IsAdmin, &p.CreatedAt, &p.UpdatedAt)
	return &p, err
}

func (s *Store) SetBGGUsername(ctx context.Context, userID, bggUsername string) error {
	tag, err := s.db.Exec(ctx,
		`UPDATE profile.users SET bgg_username = $1, updated_at = now() WHERE id = $2`,
		bggUsername, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apierr.ErrNotFound
	}
	return nil
}

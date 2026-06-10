package profile

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

type Store struct {
	db *pgxpool.Pool
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

// ref: auth.MULTI_TENANCY.1 — every query on user-owned data scoped by user_id
// ref: auth.MULTI_TENANCY.2 — user identity from request context via httpx.UserIDFromContext
// ref: profile.ADMIN.1 — is_admin stored in profile.users table
func (s *Store) GetProfile(ctx context.Context, userID string) (*Profile, error) {
	var p Profile
	err := s.db.QueryRow(ctx,
		`SELECT id, COALESCE(username, ''), bgg_username, is_admin, created_at, updated_at
		 FROM profile.users WHERE id = $1`, userID).
		Scan(&p.ID, &p.Username, &p.BGGUsername, &p.IsAdmin, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, apierr.ErrNotFound
		}
		return nil, err
	}
	return &p, nil
}

func (s *Store) UpsertProfile(ctx context.Context, userID string) (*Profile, error) {
	var p Profile
	err := s.db.QueryRow(ctx,
		`INSERT INTO profile.users (id)
		 VALUES ($1)
		 ON CONFLICT (id) DO UPDATE SET updated_at = now()
		 RETURNING id, COALESCE(username, ''), bgg_username, is_admin, created_at, updated_at`,
		userID).
		Scan(&p.ID, &p.Username, &p.BGGUsername, &p.IsAdmin, &p.CreatedAt, &p.UpdatedAt)
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

// GetBGGUsername returns the configured BGG handle for the user, or "" if unset.
func (s *Store) GetBGGUsername(ctx context.Context, userID string) (string, error) {
	var username *string
	err := s.db.QueryRow(ctx, `SELECT bgg_username FROM profile.users WHERE id = $1`, userID).Scan(&username)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	if username == nil {
		return "", nil
	}
	return *username, nil
}

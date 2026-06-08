package auth

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	db *pgxpool.Pool
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

// EmailByUsername resolves a login username to the Supabase auth email via an
// indexed lookup on profile.users joined to auth.users. Returns pgx.ErrNoRows
// when no match exists.
func (s *Store) EmailByUsername(ctx context.Context, username string) (string, error) {
	var email string
	err := s.db.QueryRow(ctx, `
		SELECT u.email
		FROM auth.users u
		JOIN profile.users p ON p.id = u.id
		WHERE lower(p.username) = lower($1)
	`, username).Scan(&email)
	return email, err
}

package auth

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	db *pgxpool.Pool
}

type Profile struct {
	ID           string
	BGGUsername  string
	IsAdmin      bool
	CreatedAt    string
	LastModified string
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) GetProfile(ctx context.Context, userID string) (*Profile, error) {
	var p Profile
	err := s.db.QueryRow(ctx, `
		SELECT id, bgg_username, is_admin, created_at, last_modified
		FROM profiles
		WHERE id = $1
	`, userID).Scan(&p.ID, &p.BGGUsername, &p.IsAdmin, &p.CreatedAt, &p.LastModified)
	return &p, err
}

package game

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	db      *pgxpool.Pool
	dataDir string
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
	// TODO: full-text search with tsvector + filters
	return nil, 0, fmt.Errorf("not implemented")
}

func (s *Store) GetGame(ctx context.Context, id int64, userID string) (*Game, error) {
	// TODO: fetch game + collections + player aids
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) CreateGame(ctx context.Context, userID string, bggID int) (int64, error) {
	// TODO: INSERT INTO games.games ...
	return 0, fmt.Errorf("not implemented")
}

// ref: auth.MULTI_TENANCY.1 — WHERE user_id = $1 scopes all queries to the owner
func (s *Store) GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error) {
	var exists bool
	err := s.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM games.games WHERE user_id = $1 AND bgg_id = $2)`,
		userID, bggID).Scan(&exists)
	return exists, err
}

// ref: game-detail.DELETE.3 — verifies user_id matches game owner before deletion
// ref: auth.MULTI_TENANCY.3 — mutation verifies user_id from JWT matches resource owner
func (s *Store) DeleteGame(ctx context.Context, id int64, userID string) error {
	tag, err := s.db.Exec(ctx,
		`DELETE FROM games.games WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("not found")
	}
	return nil
}

func (s *Store) ListCollections(ctx context.Context, userID string) ([]Collection, error) {
	// TODO: SELECT ... FROM games.collections WHERE user_id = $1 ORDER BY name
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) CreateCollection(ctx context.Context, userID, name, description string) (*Collection, error) {
	// TODO: INSERT INTO games.collections ...
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) UpdateCollection(ctx context.Context, id int64, userID, name, description string) error {
	// TODO: UPDATE games.collections ...
	return fmt.Errorf("not implemented")
}

// ref: auth.MULTI_TENANCY.3 — verifies user_id before deleting collection
func (s *Store) DeleteCollection(ctx context.Context, id int64, userID string) error {
	tag, err := s.db.Exec(ctx,
		`DELETE FROM games.collections WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("not found")
	}
	return nil
}

func (s *Store) SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
	// TODO: transaction — delete existing, insert new
	return fmt.Errorf("not implemented")
}

func (s *Store) UpdateRulesURL(ctx context.Context, gameID int64, userID, rulesURL string) error {
	tag, err := s.db.Exec(ctx,
		`UPDATE games.games SET rules_url = $1, updated_at = now()
		 WHERE id = $2 AND user_id = $3`, rulesURL, gameID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("not found")
	}
	return nil
}

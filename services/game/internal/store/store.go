package store

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/services/game/internal/model"
)

// Store handles all database access for game-service.
type Store struct {
	db      *pgxpool.Pool
	dataDir string
}

func New(db *pgxpool.Pool, dataDir string) *Store {
	return &Store{db: db, dataDir: dataDir}
}

// --- Games ---

func (s *Store) ListGames(ctx context.Context, userID string, f model.GameFilter) ([]model.Game, int, error) {
	// TODO: full-text search with tsvector + filters
	// SELECT ... FROM games.games WHERE user_id = $1
	//   AND ($2 = '' OR search_vector @@ plainto_tsquery('english', $2))
	//   ...
	return nil, 0, fmt.Errorf("not implemented")
}

func (s *Store) GetGame(ctx context.Context, id int64, userID string) (*model.Game, error) {
	// TODO: fetch game + collections + player aids
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) CreateGame(ctx context.Context, g *model.Game) (int64, error) {
	// TODO: INSERT INTO games.games ...
	return 0, fmt.Errorf("not implemented")
}

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

// --- Collections ---

func (s *Store) ListCollections(ctx context.Context, userID string) ([]model.Collection, error) {
	// TODO: SELECT ... FROM games.collections WHERE user_id = $1 ORDER BY name
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) CreateCollection(ctx context.Context, userID, name, description string) (*model.Collection, error) {
	// TODO: INSERT INTO games.collections ...
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) UpdateCollection(ctx context.Context, id int64, userID, name, description string) error {
	// TODO: UPDATE games.collections ...
	return fmt.Errorf("not implemented")
}

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

// --- Player aids ---

func (s *Store) GetPlayerAid(ctx context.Context, id int64) (*model.PlayerAid, error) {
	// TODO: SELECT ... FROM games.player_aids WHERE id = $1
	return nil, fmt.Errorf("not implemented")
}

func (s *Store) CreatePlayerAid(ctx context.Context, gameID int64, filename, label string) (int64, error) {
	// TODO: INSERT INTO games.player_aids ...
	return 0, fmt.Errorf("not implemented")
}

func (s *Store) DeletePlayerAid(ctx context.Context, id int64) error {
	// TODO: DELETE FROM games.player_aids WHERE id = $1
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

// Package collections manages user-created game playlists (collections).
package collections

import (
	"database/sql"
	"fmt"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/model"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/apierr"
)

// Store handles all collection database operations.
type Store struct{ db *sql.DB }

// NewStore wraps the shared DB connection.
func NewStore(db *sql.DB) *Store { return &Store{db: db} }

// AllCollections returns all collections owned by userID with game counts.
func (s *Store) AllCollections(userID int64) ([]model.Collection, error) {
	rows, err := s.db.Query(`
		SELECT c.id, c.user_id, c.name, c.description, c.created_at,
		       COUNT(cg.game_id) AS game_count
		FROM collections c
		LEFT JOIN collection_games cg ON cg.collection_id = c.id
		WHERE c.user_id = ?
		GROUP BY c.id
		ORDER BY c.name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []model.Collection
	for rows.Next() {
		var c model.Collection
		if err := rows.Scan(&c.ID, &c.UserID, &c.Name, &c.Description, &c.CreatedAt, &c.GameCount); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// GetCollection returns a single collection by ID, verifying ownership.
func (s *Store) GetCollection(id, userID int64) (model.Collection, error) {
	var c model.Collection
	err := s.db.QueryRow(`
		SELECT id, user_id, name, description, created_at
		FROM collections WHERE id = ? AND user_id = ?`, id, userID,
	).Scan(&c.ID, &c.UserID, &c.Name, &c.Description, &c.CreatedAt)
	return c, err
}

// CreateCollection inserts a new collection owned by userID and returns its ID.
func (s *Store) CreateCollection(name, description string, userID int64) (int64, error) {
	res, err := s.db.Exec(
		"INSERT INTO collections (user_id, name, description) VALUES (?, ?, ?)",
		userID, name, description,
	)
	if err != nil {
		if apierr.IsDuplicate(err) {
			return 0, apierr.ErrDuplicate
		}
		return 0, err
	}
	return res.LastInsertId()
}

// UpdateCollection renames or redescribes a collection, verifying ownership.
func (s *Store) UpdateCollection(id int64, name, description string, userID int64) error {
	_, err := s.db.Exec(
		"UPDATE collections SET name = ?, description = ? WHERE id = ? AND user_id = ?",
		name, description, id, userID,
	)
	if apierr.IsDuplicate(err) {
		return apierr.ErrDuplicate
	}
	return err
}

// DeleteCollection removes a collection, verifying ownership.
func (s *Store) DeleteCollection(id, userID int64) error {
	_, err := s.db.Exec("DELETE FROM collections WHERE id = ? AND user_id = ?", id, userID)
	return err
}

// GamesInCollection returns all game IDs in a collection.
func (s *Store) GamesInCollection(collectionID int64) ([]int64, error) {
	rows, err := s.db.Query(
		"SELECT game_id FROM collection_games WHERE collection_id = ? ORDER BY added_at",
		collectionID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// AddGamesToCollection adds games to a collection, verifying ownership of both.
func (s *Store) AddGamesToCollection(userID, collectionID int64, gameIDs []int64) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Verify collection ownership.
	var ownerID int64
	if err := tx.QueryRow("SELECT user_id FROM collections WHERE id = ?", collectionID).Scan(&ownerID); err != nil || ownerID != userID {
		return apierr.ErrForeignOwnership
	}

	// Verify game ownership.
	if len(gameIDs) > 0 {
		placeholders := strings.TrimSuffix(strings.Repeat("?,", len(gameIDs)), ",")
		args := make([]any, 0, len(gameIDs)+1)
		args = append(args, userID)
		for _, id := range gameIDs {
			args = append(args, id)
		}
		var cnt int
		if err := tx.QueryRow(
			fmt.Sprintf("SELECT COUNT(*) FROM games WHERE user_id = ? AND id IN (%s)", placeholders),
			args...,
		).Scan(&cnt); err != nil || cnt != len(gameIDs) {
			return apierr.ErrForeignOwnership
		}
	}

	stmt, err := tx.Prepare(
		"INSERT OR IGNORE INTO collection_games (collection_id, game_id) VALUES (?, ?)",
	)
	if err != nil {
		return err
	}
	defer stmt.Close()
	for _, gid := range gameIDs {
		if _, err := stmt.Exec(collectionID, gid); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// RemoveGameFromCollection removes a game from a collection.
func (s *Store) RemoveGameFromCollection(userID, collectionID, gameID int64) error {
	// Verify ownership.
	var ownerID int64
	if err := s.db.QueryRow("SELECT user_id FROM collections WHERE id = ?", collectionID).Scan(&ownerID); err != nil || ownerID != userID {
		return apierr.ErrForeignOwnership
	}
	_, err := s.db.Exec(
		"DELETE FROM collection_games WHERE collection_id = ? AND game_id = ?",
		collectionID, gameID,
	)
	return err
}

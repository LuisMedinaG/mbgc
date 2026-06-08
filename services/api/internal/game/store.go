package game

import (
	"context"
	"fmt"
	"regexp"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ref: game-detail.RULES_URL.1 — mirror the client-side allowlist server-side to prevent
// stored XSS via javascript: URIs in <a href={rules_url}> renders.
var rulesURLRe = regexp.MustCompile(`^https://(drive|docs)\.google\.com/`)

// validateRulesURL returns ErrValidation wrapped with a message if url is non-empty
// and not in the Drive/Docs https allowlist. Empty is allowed (clears the field).
func validateRulesURL(url string) error {
	if url != "" && !rulesURLRe.MatchString(url) {
		return fmt.Errorf("%w: rules_url must be a Google Drive or Docs https URL", apierr.ErrValidation)
	}
	return nil
}

type Store struct {
	db      *pgxpool.Pool
	dataDir string
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
	// Build WHERE clause
	where := "user_id = $1"
	args := []interface{}{userID}
	argIdx := 2

	if f.Search != "" {
		where += fmt.Sprintf(" AND search_vector @@ plainto_tsquery('english', $%d)", argIdx)
		args = append(args, f.Search)
		argIdx++
	}
	if f.Category != "" {
		where += fmt.Sprintf(" AND $%d = ANY(categories)", argIdx)
		args = append(args, f.Category)
		argIdx++
	}

	// Count total
	var total int
	countSQL := fmt.Sprintf("SELECT COUNT(*) FROM games.games WHERE %s", where)
	if err := s.db.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	// Fetch page
	offset := (f.Page - 1) * f.Limit
	args = append(args, f.Limit, offset)
	sql := fmt.Sprintf(`SELECT id, user_id, bgg_id, name, description, year_published, image, thumbnail,
		min_players, max_players, playtime, categories, mechanics, types, weight, rating,
		language_dependence, recommended_players, rules_url, created_at, updated_at
		FROM games.games WHERE %s ORDER BY name LIMIT $%d OFFSET $%d`, where, argIdx, argIdx+1)

	rows, err := s.db.Query(ctx, sql, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var games []Game
	for rows.Next() {
		var g Game
		if err := rows.Scan(&g.ID, &g.UserID, &g.BGGID, &g.Name, &g.Description, &g.YearPublished,
			&g.Image, &g.Thumbnail, &g.MinPlayers, &g.MaxPlayers, &g.Playtime, &g.Categories,
			&g.Mechanics, &g.Types, &g.Weight, &g.Rating, &g.LanguageDependence,
			&g.RecommendedPlayers, &g.RulesURL, &g.CreatedAt, &g.UpdatedAt); err != nil {
			return nil, 0, err
		}
		games = append(games, g)
	}
	if games == nil {
		games = []Game{}
	}
	return games, total, rows.Err()
}

func (s *Store) GetGame(ctx context.Context, id int64, userID string) (*Game, error) {
	var g Game
	err := s.db.QueryRow(ctx, `SELECT id, user_id, bgg_id, name, description, year_published, image, thumbnail,
		min_players, max_players, playtime, categories, mechanics, types, weight, rating,
		language_dependence, recommended_players, rules_url, created_at, updated_at
		FROM games.games WHERE id = $1 AND user_id = $2`, id, userID).Scan(
		&g.ID, &g.UserID, &g.BGGID, &g.Name, &g.Description, &g.YearPublished,
		&g.Image, &g.Thumbnail, &g.MinPlayers, &g.MaxPlayers, &g.Playtime, &g.Categories,
		&g.Mechanics, &g.Types, &g.Weight, &g.Rating, &g.LanguageDependence,
		&g.RecommendedPlayers, &g.RulesURL, &g.CreatedAt, &g.UpdatedAt)
	if err != nil {
		return nil, apierr.ErrNotFound
	}
	return &g, nil
}

func (s *Store) CreateGame(ctx context.Context, userID string, bggID int) (int64, error) {
	var id int64
	err := s.db.QueryRow(ctx, `INSERT INTO games.games (user_id, bgg_id, name) VALUES ($1, $2, '')
		RETURNING id`, userID, bggID).Scan(&id)
	return id, err
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
		return apierr.ErrNotFound
	}
	return nil
}

func (s *Store) ListCollections(ctx context.Context, userID string) ([]Collection, error) {
	rows, err := s.db.Query(ctx, `SELECT c.id, c.user_id, c.name, c.description,
		COUNT(cg.game_id) AS game_count, c.created_at, c.updated_at
		FROM games.collections c
		LEFT JOIN games.collection_games cg ON c.id = cg.collection_id
		WHERE c.user_id = $1
		GROUP BY c.id, c.user_id, c.name, c.description, c.created_at, c.updated_at
		ORDER BY c.name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var cols []Collection
	for rows.Next() {
		var c Collection
		if err := rows.Scan(&c.ID, &c.UserID, &c.Name, &c.Description, &c.GameCount, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		cols = append(cols, c)
	}
	if cols == nil {
		cols = []Collection{}
	}
	return cols, rows.Err()
}

func (s *Store) CreateCollection(ctx context.Context, userID, name, description string) (*Collection, error) {
	var c Collection
	err := s.db.QueryRow(ctx, `INSERT INTO games.collections (user_id, name, description) VALUES ($1, $2, $3)
		RETURNING id, user_id, name, description, created_at, updated_at`,
		userID, name, description).Scan(&c.ID, &c.UserID, &c.Name, &c.Description, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *Store) UpdateCollection(ctx context.Context, id int64, userID, name, description string) error {
	tag, err := s.db.Exec(ctx, `UPDATE games.collections SET name = $1, description = $2, updated_at = now()
		WHERE id = $3 AND user_id = $4`, name, description, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apierr.ErrNotFound
	}
	return nil
}

// ref: auth.MULTI_TENANCY.3 — verifies user_id before deleting collection
func (s *Store) DeleteCollection(ctx context.Context, id int64, userID string) error {
	tag, err := s.db.Exec(ctx,
		`DELETE FROM games.collections WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apierr.ErrNotFound
	}
	return nil
}

func (s *Store) SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
	// Verify game ownership
	var exists bool
	if err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM games.games WHERE id = $1 AND user_id = $2)`,
		gameID, userID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return apierr.ErrNotFound
	}

	// Delete existing associations
	if _, err := s.db.Exec(ctx, `DELETE FROM games.collection_games WHERE game_id = $1`, gameID); err != nil {
		return err
	}

	// Insert new associations
	if len(collectionIDs) > 0 {
		// Verify all collections belong to user
		var count int
		if err := s.db.QueryRow(ctx, `SELECT COUNT(*) FROM games.collections WHERE id = ANY($1) AND user_id = $2`,
			collectionIDs, userID).Scan(&count); err != nil {
			return err
		}
		if count != len(collectionIDs) {
			return apierr.ErrNotFound
		}

		for _, colID := range collectionIDs {
			if _, err := s.db.Exec(ctx, `INSERT INTO games.collection_games (collection_id, game_id) VALUES ($1, $2)`,
				colID, gameID); err != nil {
				return err
			}
		}
	}
	return nil
}

type DiscoverFilter struct {
	CollectionID int64
	Type         string
	Category     string
	Mechanic     string
	Players      string
	Playtime     string
	Weight       string
	Rating       string
	Lang         string
	RecPlayers   string
}

func (s *Store) Discover(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error) {
	// Fetch collection
	var col Collection
	err := s.db.QueryRow(ctx, `SELECT c.id, c.user_id, c.name, c.description,
		COUNT(cg.game_id) AS game_count, c.created_at, c.updated_at
		FROM games.collections c
		LEFT JOIN games.collection_games cg ON c.id = cg.collection_id
		WHERE c.id = $1 AND c.user_id = $2
		GROUP BY c.id, c.user_id, c.name, c.description, c.created_at, c.updated_at`,
		f.CollectionID, userID).Scan(&col.ID, &col.UserID, &col.Name, &col.Description, &col.GameCount, &col.CreatedAt, &col.UpdatedAt)
	if err != nil {
		return nil, 0, nil, apierr.ErrNotFound
	}

	// Build query for games in this collection
	where := "g.user_id = $1 AND cg.collection_id = $2"
	args := []interface{}{userID, f.CollectionID}
	argIdx := 3

	if f.Category != "" {
		where += fmt.Sprintf(" AND $%d = ANY(g.categories)", argIdx)
		args = append(args, f.Category)
		argIdx++
	}
	if f.Mechanic != "" {
		where += fmt.Sprintf(" AND $%d = ANY(g.mechanics)", argIdx)
		args = append(args, f.Mechanic)
		argIdx++
	}

	// Count total
	var total int
	countSQL := fmt.Sprintf(`SELECT COUNT(*) FROM games.games g
		INNER JOIN games.collection_games cg ON g.id = cg.game_id
		WHERE %s`, where)
	if err := s.db.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, nil, err
	}

	// Fetch games
	sql := fmt.Sprintf(`SELECT g.id, g.user_id, g.bgg_id, g.name, g.description, g.year_published, g.image, g.thumbnail,
		g.min_players, g.max_players, g.playtime, g.categories, g.mechanics, g.types, g.weight, g.rating,
		g.language_dependence, g.recommended_players, g.rules_url, g.created_at, g.updated_at
		FROM games.games g
		INNER JOIN games.collection_games cg ON g.id = cg.game_id
		WHERE %s ORDER BY g.name LIMIT 100`, where)

	rows, err := s.db.Query(ctx, sql, args...)
	if err != nil {
		return nil, 0, nil, err
	}
	defer rows.Close()

	var games []Game
	for rows.Next() {
		var g Game
		if err := rows.Scan(&g.ID, &g.UserID, &g.BGGID, &g.Name, &g.Description, &g.YearPublished,
			&g.Image, &g.Thumbnail, &g.MinPlayers, &g.MaxPlayers, &g.Playtime, &g.Categories,
			&g.Mechanics, &g.Types, &g.Weight, &g.Rating, &g.LanguageDependence,
			&g.RecommendedPlayers, &g.RulesURL, &g.CreatedAt, &g.UpdatedAt); err != nil {
			return nil, 0, nil, err
		}
		games = append(games, g)
	}
	if games == nil {
		games = []Game{}
	}
	return games, total, &col, rows.Err()
}

// ref: auth.MULTI_TENANCY.3 — verifies user_id before updating rules URL
// ref: game-detail.RULES_URL.1 — reject non-allowlist URLs (XSS hardening)
func (s *Store) UpdateRulesURL(ctx context.Context, gameID int64, userID, rulesURL string) error {
	if err := validateRulesURL(rulesURL); err != nil {
		return err
	}
	tag, err := s.db.Exec(ctx,
		`UPDATE games.games SET rules_url = $1, updated_at = now()
		 WHERE id = $2 AND user_id = $3`, rulesURL, gameID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apierr.ErrNotFound
	}
	return nil
}

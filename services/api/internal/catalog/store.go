package catalog

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
	sq "github.com/Masterminds/squirrel"
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
	db *pgxpool.Pool
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

const gameColumns = "id, user_id, bgg_id, name, description, year_published, image, thumbnail," +
	" min_players, max_players, playtime, categories, mechanics, types, weight, rating," +
	" language_dependence, recommended_players, rules_url," +
	" (SELECT COALESCE(json_agg(json_build_object('id', c.id, 'name', c.name) ORDER BY c.name), '[]'::json)" +
	"  FROM games.collection_games cg JOIN games.collections c ON c.id = cg.collection_id" +
	"  WHERE cg.game_id = games.games.id) AS vibes," +
	" (SELECT COALESCE(json_agg(json_build_object('id', pa.id, 'game_id', pa.game_id, 'filename', pa.filename, 'label', pa.label, 'created_at', pa.created_at) ORDER BY pa.created_at), '[]'::json)" +
	"  FROM games.player_aids pa WHERE pa.game_id = games.games.id) AS player_aids," +
	" created_at, updated_at"

// scanner is satisfied by both pgx.Rows (Query) and pgx.Row (QueryRow).
type scanner interface {
	Scan(dest ...any) error
}

func scanGame(s scanner) (Game, error) {
	var g Game
	var vibesJSON []byte
	var aidsJSON []byte
	err := s.Scan(&g.ID, &g.UserID, &g.BGGID, &g.Name, &g.Description, &g.YearPublished,
		&g.Image, &g.Thumbnail, &g.MinPlayers, &g.MaxPlayers, &g.Playtime, &g.Categories,
		&g.Mechanics, &g.Types, &g.Weight, &g.Rating, &g.LanguageDependence,
		&g.RecommendedPlayers, &g.RulesURL, &vibesJSON, &aidsJSON, &g.CreatedAt, &g.UpdatedAt)
	if err != nil {
		return g, err
	}
	if err := json.Unmarshal(vibesJSON, &g.Vibes); err != nil {
		return g, err
	}
	if err := json.Unmarshal(aidsJSON, &g.PlayerAids); err != nil {
		return g, err
	}
	return g, nil
}

func scanCollection(s scanner) (Collection, error) {
	var c Collection
	err := s.Scan(&c.ID, &c.UserID, &c.Name, &c.Description, &c.GameCount, &c.CreatedAt, &c.UpdatedAt)
	return c, err
}

func scanPlayerAid(s scanner) (PlayerAid, error) {
	var a PlayerAid
	err := s.Scan(&a.ID, &a.GameID, &a.Filename, &a.Label, &a.CreatedAt)
	return a, err
}

func gamePredicates(userID string, f GameFilter) sq.And {
	pred := sq.And{sq.Eq{"user_id": userID}}
	if f.Search != "" {
		pred = append(pred, sq.Expr("search_vector @@ plainto_tsquery('english', ?)", f.Search))
	}
	if f.Category != "" {
		pred = append(pred, sq.Expr("? = ANY(categories)", f.Category))
	}
	switch f.Players {
	case "1":
		pred = append(pred, sq.LtOrEq{"min_players": 1})
	case "2":
		pred = append(pred, sq.LtOrEq{"min_players": 2})
	case "2only":
		pred = append(pred, sq.LtOrEq{"min_players": 2}, sq.GtOrEq{"max_players": 2})
	case "3":
		pred = append(pred, sq.LtOrEq{"min_players": 3})
	case "4":
		pred = append(pred, sq.LtOrEq{"min_players": 4})
	case "5plus":
		pred = append(pred, sq.GtOrEq{"max_players": 5})
	}
	switch f.Playtime {
	case "short":
		pred = append(pred, sq.Lt{"playtime": 30})
	case "medium":
		pred = append(pred, sq.GtOrEq{"playtime": 30}, sq.LtOrEq{"playtime": 60})
	case "long":
		pred = append(pred, sq.Gt{"playtime": 60})
	}
	switch f.Weight {
	case "light":
		pred = append(pred, sq.Lt{"weight": 2})
	case "medium":
		pred = append(pred, sq.GtOrEq{"weight": 2}, sq.LtOrEq{"weight": 3.5})
	case "heavy":
		pred = append(pred, sq.Gt{"weight": 3.5})
	}
	return pred
}

func (s *Store) ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
	pred := gamePredicates(userID, f)

	countSQL, countArgs, err := sq.Select("COUNT(*)").
		From("games.games").
		Where(pred).
		PlaceholderFormat(sq.Dollar).
		ToSql()
	if err != nil {
		return nil, 0, err
	}
	var total int
	if err := s.db.QueryRow(ctx, countSQL, countArgs...).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (f.Page - 1) * f.Limit
	listSQL, listArgs, err := sq.Select(gameColumns).
		From("games.games").
		Where(pred).
		OrderBy("name").
		Limit(uint64(f.Limit)).
		Offset(uint64(offset)).
		PlaceholderFormat(sq.Dollar).
		ToSql()
	if err != nil {
		return nil, 0, err
	}

	rows, err := s.db.Query(ctx, listSQL, listArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var games []Game
	for rows.Next() {
		g, err := scanGame(rows)
		if err != nil {
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
	g, err := scanGame(s.db.QueryRow(ctx,
		`SELECT `+gameColumns+` FROM games.games WHERE id = $1 AND user_id = $2`, id, userID))
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

// BGGGameData is the subset of game data fetched from BGG that we persist.
// Defined here (not in importer) to keep the DB schema and its input shape
// colocated — the importer translates BGG XML into this struct.
type BGGGameData struct {
	BGGID              int
	Name               string
	Description        string
	YearPublished      *int
	Image              *string
	Thumbnail          *string
	MinPlayers         *int
	MaxPlayers         *int
	PlayTime           *int
	Categories         []string
	Mechanics          []string
	Types              []string
	Weight             *float64
	Rating             *float64
	LanguageDependence *int
	RecommendedPlayers []int
}

// UpsertBGGGame inserts a new game from BGG or updates an existing one (matched
// by user_id + bgg_id). Returns the game id and whether it was newly created.
func (s *Store) UpsertBGGGame(ctx context.Context, userID string, g BGGGameData) (int64, bool, error) {
	name := g.Name
	if name == "" {
		name = "(unnamed BGG " + strconv.Itoa(g.BGGID) + ")"
	}
	var id int64
	var created bool
	err := s.db.QueryRow(ctx, `
		INSERT INTO games.games (
			user_id, bgg_id, name, description, year_published, image, thumbnail,
			min_players, max_players, playtime, categories, mechanics, types,
			weight, rating, language_dependence, recommended_players
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
		ON CONFLICT (user_id, bgg_id) DO UPDATE SET
			name = EXCLUDED.name,
			description = EXCLUDED.description,
			year_published = EXCLUDED.year_published,
			image = EXCLUDED.image,
			thumbnail = EXCLUDED.thumbnail,
			min_players = EXCLUDED.min_players,
			max_players = EXCLUDED.max_players,
			playtime = EXCLUDED.playtime,
			categories = EXCLUDED.categories,
			mechanics = EXCLUDED.mechanics,
			types = EXCLUDED.types,
			weight = EXCLUDED.weight,
			rating = EXCLUDED.rating,
			language_dependence = EXCLUDED.language_dependence,
			recommended_players = EXCLUDED.recommended_players,
			updated_at = now()
		RETURNING id, (xmax = 0)`,
		userID, g.BGGID, name, nullStr(g.Description), g.YearPublished, g.Image, g.Thumbnail,
		g.MinPlayers, g.MaxPlayers, g.PlayTime,
		emptySlice(g.Categories), emptySlice(g.Mechanics), emptySlice(g.Types),
		g.Weight, g.Rating, g.LanguageDependence, emptyIntSlice(g.RecommendedPlayers),
	).Scan(&id, &created)
	return id, created, err
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func emptySlice(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func emptyIntSlice(s []int) []int {
	if s == nil {
		return []int{}
	}
	return s
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
		c, err := scanCollection(rows)
		if err != nil {
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

func (s *Store) CreatePlayerAid(ctx context.Context, userID string, gameID int64, filename string, label *string) (*PlayerAid, error) {
	var exists bool
	if err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM games.games WHERE id = $1 AND user_id = $2)`,
		gameID, userID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, apierr.ErrNotFound
	}

	var pa PlayerAid
	err := s.db.QueryRow(ctx, `
		INSERT INTO games.player_aids (game_id, filename, label)
		VALUES ($1, $2, $3)
		RETURNING id, game_id, filename, label, created_at`,
		gameID, filename, label).Scan(&pa.ID, &pa.GameID, &pa.Filename, &pa.Label, &pa.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &pa, nil
}

func (s *Store) DeletePlayerAid(ctx context.Context, userID string, gameID, aidID int64) error {
	tag, err := s.db.Exec(ctx, `
		DELETE FROM games.player_aids
		WHERE id = $1 AND game_id = $2 AND game_id IN (SELECT id FROM games.games WHERE user_id = $3)`,
		aidID, gameID, userID)
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

// ref: auth.MULTI_TENANCY.3 — game + collection ownership checks and the
// DELETE/INSERT batch all run in a single pgx.Tx so a partial failure cannot
// leave the game with a stripped collection set (issue #39).
// ref: game-detail.VIBE_ASSIGN.1 — saving replaces the full set atomically.
func (s *Store) SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	// Rollback is a no-op after a successful Commit. Ignoring the error
	// avoids false-positive errcheck reports for the post-commit case
	// (which always returns ErrTxClosed, the documented sentinel).
	defer func() { _ = tx.Rollback(ctx) }()

	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM games.games WHERE id = $1 AND user_id = $2)`,
		gameID, userID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return apierr.ErrNotFound
	}

	if _, err := tx.Exec(ctx, `DELETE FROM games.collection_games WHERE game_id = $1`, gameID); err != nil {
		return err
	}

	if len(collectionIDs) > 0 {
		var count int
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM games.collections WHERE id = ANY($1) AND user_id = $2`,
			collectionIDs, userID).Scan(&count); err != nil {
			return err
		}
		if count != len(collectionIDs) {
			return apierr.ErrNotFound
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO games.collection_games (collection_id, game_id)
			SELECT unnest($1::bigint[]), $2`,
			collectionIDs, gameID); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

type DiscoverFilter struct {
	CollectionID int64
	Category     string
	Mechanic     string
	Page         int
	Limit        int
}

func (s *Store) Discover(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error) {
	col, err := scanCollection(s.db.QueryRow(ctx, `SELECT c.id, c.user_id, c.name, c.description,
		COUNT(cg.game_id) AS game_count, c.created_at, c.updated_at
		FROM games.collections c
		LEFT JOIN games.collection_games cg ON c.id = cg.collection_id
		WHERE c.id = $1 AND c.user_id = $2
		GROUP BY c.id, c.user_id, c.name, c.description, c.created_at, c.updated_at`,
		f.CollectionID, userID))
	if err != nil {
		return nil, 0, nil, apierr.ErrNotFound
	}

	pred := sq.And{
		sq.Expr("g.user_id = ?", userID),
		sq.Expr("cg.collection_id = ?", f.CollectionID),
	}
	if f.Category != "" {
		pred = append(pred, sq.Expr("? = ANY(g.categories)", f.Category))
	}
	if f.Mechanic != "" {
		pred = append(pred, sq.Expr("? = ANY(g.mechanics)", f.Mechanic))
	}

	countSQL, countArgs, err := sq.Select("COUNT(*)").
		From("games.games g").
		Join("games.collection_games cg ON g.id = cg.game_id").
		Where(pred).
		PlaceholderFormat(sq.Dollar).
		ToSql()
	if err != nil {
		return nil, 0, nil, err
	}
	var total int
	if err := s.db.QueryRow(ctx, countSQL, countArgs...).Scan(&total); err != nil {
		return nil, 0, nil, err
	}

	listSQL, listArgs, err := sq.Select(
		"g.id, g.user_id, g.bgg_id, g.name, g.description, g.year_published, g.image, g.thumbnail," +
			" g.min_players, g.max_players, g.playtime, g.categories, g.mechanics, g.types, g.weight, g.rating," +
			" g.language_dependence, g.recommended_players, g.rules_url," +
			" (SELECT COALESCE(json_agg(json_build_object('id', c2.id, 'name', c2.name) ORDER BY c2.name), '[]'::json)" +
			"  FROM games.collection_games cg2 JOIN games.collections c2 ON c2.id = cg2.collection_id" +
			"  WHERE cg2.game_id = g.id) AS vibes," +
			" (SELECT COALESCE(json_agg(json_build_object('id', pa.id, 'game_id', pa.game_id, 'filename', pa.filename, 'label', pa.label, 'created_at', pa.created_at) ORDER BY pa.created_at), '[]'::json)" +
			"  FROM games.player_aids pa WHERE pa.game_id = g.id) AS player_aids," +
			" g.created_at, g.updated_at").
		From("games.games g").
		Join("games.collection_games cg ON g.id = cg.game_id").
		Where(pred).
		OrderBy("g.name").
		Limit(uint64(f.Limit)).
		Offset(uint64((f.Page - 1) * f.Limit)).
		PlaceholderFormat(sq.Dollar).
		ToSql()
	if err != nil {
		return nil, 0, nil, err
	}

	rows, err := s.db.Query(ctx, listSQL, listArgs...)
	if err != nil {
		return nil, 0, nil, err
	}
	defer rows.Close()

	var games []Game
	for rows.Next() {
		g, err := scanGame(rows)
		if err != nil {
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

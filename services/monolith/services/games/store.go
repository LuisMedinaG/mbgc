package games

import (
	"database/sql"
	"fmt"
	"regexp"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/model"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/apierr"
)

// Store handles all game-related database operations.
type Store struct{ db *sql.DB }

// NewStore wraps the shared DB connection.
func NewStore(db *sql.DB) *Store { return &Store{db: db} }

// ── Constants ─────────────────────────────────────────────────────────────────

// DefaultPageSize is the default number of games per page.
const DefaultPageSize = 20

// MaxPageSize caps the client-supplied limit to prevent abuse.
const MaxPageSize = 300

// ── Game CRUD ─────────────────────────────────────────────────────────────────

const gameColumns = `id, bgg_id, name, description, year_published, image, thumbnail,
	min_players, max_players, play_time, categories, mechanics, types, weight,
	rules_url, rating, language_dependence, recommended_players`

func scanGame(row interface{ Scan(...any) error }) (model.Game, error) {
	var g model.Game
	err := row.Scan(
		&g.ID, &g.BGGID, &g.Name, &g.Description, &g.YearPublished,
		&g.Image, &g.Thumbnail, &g.MinPlayers, &g.MaxPlayers, &g.PlayTime,
		&g.Categories, &g.Mechanics, &g.Types, &g.Weight,
		&g.RulesURL, &g.Rating, &g.LanguageDependence, &g.RecommendedPlayers,
	)
	return g, err
}

func scanGames(rows *sql.Rows) ([]model.Game, error) {
	var games []model.Game
	for rows.Next() {
		g, err := scanGame(rows)
		if err != nil {
			return nil, err
		}
		games = append(games, g)
	}
	return games, rows.Err()
}

// GetGame returns a single game by ID, verifying ownership.
func (s *Store) GetGame(id, userID int64) (model.Game, error) {
	return scanGame(s.db.QueryRow(
		"SELECT "+gameColumns+" FROM games WHERE id = ? AND user_id = ?", id, userID,
	))
}

// GetGameByBGGID returns a game by BGG ID for the given user.
func (s *Store) GetGameByBGGID(bggID, userID int64) (model.Game, error) {
	return scanGame(s.db.QueryRow(
		"SELECT "+gameColumns+" FROM games WHERE bgg_id = ? AND user_id = ?", bggID, userID,
	))
}

// GetThumbnailByBGGID returns the thumbnail URL for any game with the given BGG ID.
func (s *Store) GetThumbnailByBGGID(bggID int64) (string, error) {
	var thumbnail string
	err := s.db.QueryRow("SELECT thumbnail FROM games WHERE bgg_id = ? LIMIT 1", bggID).Scan(&thumbnail)
	return thumbnail, err
}

// CreateGame inserts a new game owned by userID and returns its ID.
func (s *Store) CreateGame(g model.Game, userID int64) (int64, error) {
	res, err := s.db.Exec(
		`INSERT INTO games (bgg_id, name, description, year_published, image, thumbnail,
			min_players, max_players, play_time, categories, mechanics, types, weight,
			rules_url, rating, language_dependence, recommended_players, user_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		g.BGGID, g.Name, g.Description, g.YearPublished, g.Image, g.Thumbnail,
		g.MinPlayers, g.MaxPlayers, g.PlayTime, g.Categories, g.Mechanics, g.Types, g.Weight,
		g.RulesURL, g.Rating, g.LanguageDependence, g.RecommendedPlayers, userID,
	)
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	if err := s.upsertGameTaxonomy(id, g.Categories, g.Mechanics); err != nil {
		return id, err
	}
	return id, nil
}

// UpdateGame refreshes a game's BGG data for the given user.
func (s *Store) UpdateGame(g model.Game, userID int64) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	res, err := tx.Exec(
		`UPDATE games SET name=?, description=?, year_published=?, image=?, thumbnail=?,
			min_players=?, max_players=?, play_time=?, categories=?, mechanics=?, types=?,
			weight=?, rating=?, language_dependence=?, recommended_players=?
		WHERE bgg_id=? AND user_id=?`,
		g.Name, g.Description, g.YearPublished, g.Image, g.Thumbnail,
		g.MinPlayers, g.MaxPlayers, g.PlayTime, g.Categories, g.Mechanics, g.Types,
		g.Weight, g.Rating, g.LanguageDependence, g.RecommendedPlayers,
		g.BGGID, userID,
	)
	if err != nil {
		return err
	}

	rows, _ := res.RowsAffected()
	if rows == 0 {
		return nil
	}
	var gameID int64
	if err := tx.QueryRow("SELECT id FROM games WHERE bgg_id = ? AND user_id = ?", g.BGGID, userID).Scan(&gameID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM game_categories WHERE game_id = ?", gameID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM game_mechanics WHERE game_id = ?", gameID); err != nil {
		return err
	}
	if err := upsertGameTaxonomyTx(tx, gameID, g.Categories, g.Mechanics); err != nil {
		return err
	}
	return tx.Commit()
}

// UpdateGameRulesURL sets the rules URL for a game owned by userID.
func (s *Store) UpdateGameRulesURL(id int64, rulesURL string, userID int64) error {
	_, err := s.db.Exec(
		"UPDATE games SET rules_url = ? WHERE id = ? AND user_id = ?", rulesURL, id, userID,
	)
	return err
}

// DeleteGame removes a game owned by userID.
func (s *Store) DeleteGame(id, userID int64) error {
	_, err := s.db.Exec("DELETE FROM games WHERE id = ? AND user_id = ?", id, userID)
	return err
}

// GameCount returns the total number of games owned by userID.
func (s *Store) GameCount(userID int64) int {
	var count int
	_ = s.db.QueryRow("SELECT COUNT(*) FROM games WHERE user_id = ?", userID).Scan(&count)
	return count
}

// OwnedBGGIDs returns a set of BGG IDs already in the user's collection.
func (s *Store) OwnedBGGIDs(userID int64) (map[int64]bool, error) {
	rows, err := s.db.Query("SELECT bgg_id FROM games WHERE user_id = ?", userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := make(map[int64]bool)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		m[id] = true
	}
	return m, rows.Err()
}

// ── Filtering ─────────────────────────────────────────────────────────────────

var ftsSpecialChars = regexp.MustCompile(`[^a-zA-Z0-9 ]`)

func sanitizeFTSQuery(q string) string {
	safe := strings.TrimSpace(ftsSpecialChars.ReplaceAllString(q, " "))
	words := strings.Fields(safe)
	for i, w := range words {
		words[i] = w + "*"
	}
	return strings.Join(words, " ")
}

func buildGameConditions(q, category, players, playtime, weight, rating, lang, recPlayers string, userID int64) ([]string, []any) {
	conds := []string{"user_id = ?"}
	args := []any{userID}

	if q != "" {
		if safe := sanitizeFTSQuery(q); safe != "" {
			conds = append(conds, "id IN (SELECT rowid FROM games_fts WHERE games_fts MATCH ?)")
			args = append(args, safe)
		}
	}
	if category != "" {
		conds = append(conds, "id IN (SELECT game_id FROM game_categories gc JOIN categories c ON c.id = gc.category_id WHERE c.name = ?)")
		args = append(args, category)
	}

	filters := []struct {
		fn  func(string, string) string
		val string
	}{
		{PlayerCondition, players},
		{PlaytimeCondition, playtime},
		{WeightCondition, weight},
		{RatingCondition, rating},
		{LanguageCondition, lang},
		{RecommendedPlayersCondition, recPlayers},
	}
	for _, f := range filters {
		if cond := f.fn(f.val, ""); cond != "" {
			conds = append(conds, cond)
		}
	}
	return conds, args
}

// FilterGames returns a page of games matching the given filters plus total count.
func (s *Store) FilterGames(q, category, players, playtime, weight, rating, lang, recPlayers string, page, pageSize int, userID int64) ([]model.Game, int, error) {
	conds, args := buildGameConditions(q, category, players, playtime, weight, rating, lang, recPlayers, userID)
	where := " WHERE " + strings.Join(conds, " AND ")

	var total int
	if err := s.db.QueryRow("SELECT COUNT(*) FROM games"+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	if page < 1 {
		page = 1
	}
	offset := (page - 1) * pageSize
	rows, err := s.db.Query(
		"SELECT "+gameColumns+" FROM games"+where+" ORDER BY name LIMIT ? OFFSET ?",
		append(args, pageSize, offset)...,
	)
	if err != nil {
		return nil, total, err
	}
	defer rows.Close()
	games, err := scanGames(rows)
	return games, total, err
}

// FilterGamesByCollection returns games in a collection owned by userID, with optional filters.
func (s *Store) FilterGamesByCollection(collectionID int64, typ, category, mechanic, players, playtime, weight, rating, lang, recPlayers string, userID int64) ([]model.Game, error) {
	conds := []string{
		"g.user_id = ?",
		"g.id IN (SELECT game_id FROM collection_games WHERE collection_id = ?)",
	}
	args := []any{userID, collectionID}

	if typ != "" {
		conds = append(conds, "g.types LIKE ?")
		args = append(args, "%"+typ+"%")
	}
	if category != "" {
		conds = append(conds, "g.id IN (SELECT game_id FROM game_categories gc JOIN categories c ON c.id = gc.category_id WHERE c.name = ?)")
		args = append(args, category)
	}
	if mechanic != "" {
		conds = append(conds, "g.id IN (SELECT game_id FROM game_mechanics gm JOIN mechanics m ON m.id = gm.mechanic_id WHERE m.name = ?)")
		args = append(args, mechanic)
	}
	for _, fn := range []struct {
		f   func(string, string) string
		val string
	}{
		{PlayerCondition, players},
		{PlaytimeCondition, playtime},
		{WeightCondition, weight},
		{RatingCondition, rating},
		{LanguageCondition, lang},
		{RecommendedPlayersCondition, recPlayers},
	} {
		if cond := fn.f(fn.val, "g."); cond != "" {
			conds = append(conds, cond)
		}
	}

	query := `SELECT g.id, g.bgg_id, g.name, g.description, g.year_published, g.image, g.thumbnail,
		g.min_players, g.max_players, g.play_time, g.categories, g.mechanics, g.types, g.weight,
		g.rules_url, g.rating, g.language_dependence, g.recommended_players
		FROM games g WHERE ` + strings.Join(conds, " AND ") + " ORDER BY g.name"

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanGames(rows)
}

// DistinctCategories returns all category names for the user's games.
func (s *Store) DistinctCategories(userID int64) ([]string, error) {
	rows, err := s.db.Query(`
		SELECT DISTINCT c.name
		FROM categories c
		JOIN game_categories gc ON c.id = gc.category_id
		JOIN games g ON g.id = gc.game_id
		WHERE g.user_id = ?
		ORDER BY c.name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var cats []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		cats = append(cats, name)
	}
	return cats, rows.Err()
}

// ── Collections on games ──────────────────────────────────────────────────────

// CollectionsForGame returns all collection IDs + names associated with a game.
func (s *Store) CollectionsForGame(gameID int64) ([]model.Collection, error) {
	rows, err := s.db.Query(`
		SELECT c.id, c.user_id, c.name, c.description, c.created_at
		FROM collections c
		JOIN collection_games cg ON cg.collection_id = c.id
		WHERE cg.game_id = ?
		ORDER BY c.name`, gameID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCollections(rows)
}

// CollectionsForGames returns a map of game ID → collections.
func (s *Store) CollectionsForGames(gameIDs []int64) (map[int64][]model.Collection, error) {
	if len(gameIDs) == 0 {
		return nil, nil
	}
	placeholders := strings.Repeat("?,", len(gameIDs))
	placeholders = placeholders[:len(placeholders)-1]
	args := make([]any, len(gameIDs))
	for i, id := range gameIDs {
		args[i] = id
	}
	rows, err := s.db.Query(fmt.Sprintf(`
		SELECT cg.game_id, c.id, c.user_id, c.name, c.description, c.created_at
		FROM collection_games cg
		JOIN collections c ON c.id = cg.collection_id
		WHERE cg.game_id IN (%s)
		ORDER BY c.name`, placeholders), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[int64][]model.Collection)
	for rows.Next() {
		var gameID int64
		var c model.Collection
		if err := rows.Scan(&gameID, &c.ID, &c.UserID, &c.Name, &c.Description, &c.CreatedAt); err != nil {
			return nil, err
		}
		result[gameID] = append(result[gameID], c)
	}
	return result, rows.Err()
}

// SetGameCollections replaces all collection associations for a game.
func (s *Store) SetGameCollections(userID, gameID int64, collectionIDs []int64) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	collectionIDs = uniqueIDs(collectionIDs)

	ownedGames, err := ownedIDs(tx, "games", userID, []int64{gameID})
	if err != nil {
		return err
	}
	if !ownedGames[gameID] {
		return apierr.ErrForeignOwnership
	}

	if len(collectionIDs) > 0 {
		ownedCols, err := ownedIDs(tx, "collections", userID, collectionIDs)
		if err != nil {
			return err
		}
		if len(ownedCols) != len(collectionIDs) {
			return apierr.ErrForeignOwnership
		}
	}

	if _, err := tx.Exec("DELETE FROM collection_games WHERE game_id = ?", gameID); err != nil {
		return err
	}
	for _, cid := range collectionIDs {
		if _, err := tx.Exec(
			"INSERT INTO collection_games (collection_id, game_id) VALUES (?, ?)", cid, gameID,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// AddGamesToCollections adds collections to multiple games owned by userID.
func (s *Store) AddGamesToCollections(userID int64, gameIDs, collectionIDs []int64) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	gameIDs = uniqueIDs(gameIDs)
	collectionIDs = uniqueIDs(collectionIDs)

	ownedGames, err := ownedIDs(tx, "games", userID, gameIDs)
	if err != nil {
		return err
	}
	if len(ownedGames) != len(gameIDs) {
		return apierr.ErrForeignOwnership
	}

	ownedCols, err := ownedIDs(tx, "collections", userID, collectionIDs)
	if err != nil {
		return err
	}
	if len(ownedCols) != len(collectionIDs) {
		return apierr.ErrForeignOwnership
	}

	stmt, err := tx.Prepare("INSERT OR IGNORE INTO collection_games (collection_id, game_id) VALUES (?, ?)")
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, gid := range gameIDs {
		for _, cid := range collectionIDs {
			if _, err := stmt.Exec(cid, gid); err != nil {
				return err
			}
		}
	}
	return tx.Commit()
}

// ── Player aids ───────────────────────────────────────────────────────────────

// GetPlayerAids returns all player aids for a game.
func (s *Store) GetPlayerAids(gameID int64) ([]model.PlayerAid, error) {
	rows, err := s.db.Query(
		"SELECT id, game_id, filename, label FROM player_aids WHERE game_id = ? ORDER BY id",
		gameID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var aids []model.PlayerAid
	for rows.Next() {
		var a model.PlayerAid
		if err := rows.Scan(&a.ID, &a.GameID, &a.Filename, &a.Label); err != nil {
			return nil, err
		}
		aids = append(aids, a)
	}
	return aids, rows.Err()
}

// GetPlayerAid returns a single player aid by ID.
func (s *Store) GetPlayerAid(id int64) (model.PlayerAid, error) {
	var a model.PlayerAid
	err := s.db.QueryRow(
		"SELECT id, game_id, filename, label FROM player_aids WHERE id = ?", id,
	).Scan(&a.ID, &a.GameID, &a.Filename, &a.Label)
	return a, err
}

// CreatePlayerAid inserts a new player aid and returns its ID.
func (s *Store) CreatePlayerAid(gameID int64, filename, label string) (int64, error) {
	res, err := s.db.Exec(
		"INSERT INTO player_aids (game_id, filename, label) VALUES (?, ?, ?)", gameID, filename, label,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// DeletePlayerAid removes a player aid by ID.
func (s *Store) DeletePlayerAid(id int64) error {
	_, err := s.db.Exec("DELETE FROM player_aids WHERE id = ?", id)
	return err
}

// ── Taxonomy ──────────────────────────────────────────────────────────────────

// PopulateTaxonomy fills the normalized category and mechanic tables from
// existing game rows. Safe to call on every startup (uses INSERT OR IGNORE).
func (s *Store) PopulateTaxonomy() error {
	rows, err := s.db.Query("SELECT id, categories, mechanics FROM games")
	if err != nil {
		return err
	}
	defer rows.Close()

	type entry struct {
		id         int64
		categories string
		mechanics  string
	}
	var entries []entry
	for rows.Next() {
		var e entry
		if err := rows.Scan(&e.id, &e.categories, &e.mechanics); err != nil {
			return err
		}
		entries = append(entries, e)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, e := range entries {
		if err := s.upsertGameTaxonomy(e.id, e.categories, e.mechanics); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) upsertGameTaxonomy(gameID int64, categories, mechanics string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := upsertGameTaxonomyTx(tx, gameID, categories, mechanics); err != nil {
		return err
	}
	return tx.Commit()
}

func upsertGameTaxonomyTx(tx *sql.Tx, gameID int64, categories, mechanics string) error {
	if err := upsertTaxonomyItems(tx, gameID, "categories", "game_categories", "category_id", splitTaxonomy(categories)); err != nil {
		return err
	}
	return upsertTaxonomyItems(tx, gameID, "mechanics", "game_mechanics", "mechanic_id", splitTaxonomy(mechanics))
}

func upsertTaxonomyItems(tx *sql.Tx, gameID int64, table, joinTable, fkColumn string, items []string) error {
	for _, name := range items {
		if _, err := tx.Exec(fmt.Sprintf("INSERT OR IGNORE INTO %s (name) VALUES (?)", table), name); err != nil {
			return err
		}
		if _, err := tx.Exec(
			fmt.Sprintf("INSERT OR IGNORE INTO %s (game_id, %s) SELECT ?, id FROM %s WHERE name = ?", joinTable, fkColumn, table),
			gameID, name,
		); err != nil {
			return err
		}
	}
	return nil
}

func splitTaxonomy(s string) []string {
	var out []string
	for _, v := range strings.Split(s, ", ") {
		v = strings.TrimSpace(v)
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}

// ── Config ────────────────────────────────────────────────────────────────────

// GetConfig returns a config value, or "" when absent.
func (s *Store) GetConfig(key string) string {
	var v string
	_ = s.db.QueryRow("SELECT value FROM config WHERE key = ?", key).Scan(&v)
	return v
}

// SetConfig upserts a config key-value pair.
func (s *Store) SetConfig(key, value string) error {
	_, err := s.db.Exec(
		"INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?",
		key, value, value,
	)
	return err
}

// ── Seeding ───────────────────────────────────────────────────────────────────

// SeedIfEmpty populates the games table with sample data when the user has none.
func (s *Store) SeedIfEmpty(userID int64) error {
	var count int
	if err := s.db.QueryRow("SELECT COUNT(*) FROM games WHERE user_id = ?", userID).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil
	}
	seeds := []model.Game{
		{
			BGGID: 13, Name: "Catan", YearPublished: 1995,
			Description: "Collect and trade resources to build up the island of Catan.",
			MinPlayers: 3, MaxPlayers: 4, PlayTime: 90,
			Categories: "Economic, Negotiation",
			Mechanics:  "Dice Rolling, Hand Management, Trading",
			Types:      "Family Games, Strategy Games",
		},
		{
			BGGID: 178900, Name: "Codenames", YearPublished: 2015,
			Description: "Give one-word clues to help your team identify secret agents.",
			MinPlayers: 2, MaxPlayers: 8, PlayTime: 15,
			Categories: "Card Game, Party Game, Word Game",
			Mechanics:  "Communication Limits, Team-Based Game",
			Types:      "Family Games, Party Games",
		},
		{
			BGGID: 174430, Name: "Gloomhaven", YearPublished: 2017,
			Description: "Vanquish monsters with strategic cardplay in a persistent legacy campaign.",
			MinPlayers: 1, MaxPlayers: 4, PlayTime: 120,
			Categories: "Adventure, Fantasy, Fighting",
			Mechanics:  "Action Queue, Campaign, Cooperative Game",
			Types:      "Strategy Games, Thematic Games",
		},
	}
	for _, g := range seeds {
		if _, err := s.CreateGame(g, userID); err != nil {
			return fmt.Errorf("seed %q: %w", g.Name, err)
		}
	}
	return nil
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func scanCollections(rows *sql.Rows) ([]model.Collection, error) {
	var out []model.Collection
	for rows.Next() {
		var c model.Collection
		if err := rows.Scan(&c.ID, &c.UserID, &c.Name, &c.Description, &c.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func uniqueIDs(ids []int64) []int64 {
	if len(ids) < 2 {
		return ids
	}
	seen := make(map[int64]struct{}, len(ids))
	out := make([]int64, 0, len(ids))
	for _, id := range ids {
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func ownedIDs(tx *sql.Tx, table string, userID int64, ids []int64) (map[int64]bool, error) {
	ids = uniqueIDs(ids)
	if len(ids) == 0 {
		return map[int64]bool{}, nil
	}
	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(ids)), ",")
	query := fmt.Sprintf("SELECT id FROM %s WHERE user_id = ? AND id IN (%s)", table, placeholders)
	args := make([]any, 0, len(ids)+1)
	args = append(args, userID)
	for _, id := range ids {
		args = append(args, id)
	}
	rows, err := tx.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[int64]bool, len(ids))
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		result[id] = true
	}
	return result, rows.Err()
}

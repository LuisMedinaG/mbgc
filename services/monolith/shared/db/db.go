// Package db opens and migrates the SQLite database shared across all services.
package db

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strings"

	"golang.org/x/crypto/argon2"
	_ "modernc.org/sqlite"
)

const (
	argon2idMemory      = 64 * 1024
	argon2idTime        = 1
	argon2idParallelism = 4
	argon2idKeyLen      = 32
	argon2idSaltLen     = 16
)

// Open opens (or creates) the SQLite database at path, applies all schema
// migrations, and returns the ready connection. The caller is responsible for
// calling Close on the returned DB.
func Open(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	if err = db.Ping(); err != nil {
		db.Close()
		return nil, err
	}
	_, _ = db.Exec("PRAGMA journal_mode=WAL")
	_, _ = db.Exec("PRAGMA foreign_keys=ON")

	if err := createTables(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := migrateUserData(db); err != nil {
		db.Close()
		return nil, err
	}
	if err := migrateTestUser(db); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func createTables(db *sql.DB) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS games (
			id                  INTEGER PRIMARY KEY AUTOINCREMENT,
			bgg_id              INTEGER NOT NULL,
			name                TEXT    NOT NULL,
			description         TEXT    NOT NULL DEFAULT '',
			year_published      INTEGER NOT NULL DEFAULT 0,
			image               TEXT    NOT NULL DEFAULT '',
			thumbnail           TEXT    NOT NULL DEFAULT '',
			min_players         INTEGER NOT NULL DEFAULT 1,
			max_players         INTEGER NOT NULL DEFAULT 4,
			play_time           INTEGER NOT NULL DEFAULT 30,
			categories          TEXT    NOT NULL DEFAULT '',
			mechanics           TEXT    NOT NULL DEFAULT '',
			rules_url           TEXT    NOT NULL DEFAULT '',
			user_id             INTEGER,
			UNIQUE (user_id, bgg_id)
		)`,
		`CREATE TABLE IF NOT EXISTS player_aids (
			id       INTEGER PRIMARY KEY AUTOINCREMENT,
			game_id  INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
			filename TEXT    NOT NULL,
			label    TEXT    NOT NULL DEFAULT ''
		)`,
		`CREATE TABLE IF NOT EXISTS config (
			key   TEXT PRIMARY KEY,
			value TEXT NOT NULL DEFAULT ''
		)`,
		// Legacy vibe tables — kept for data migration; new code uses collections.
		`CREATE TABLE IF NOT EXISTS vibes (
			id      INTEGER PRIMARY KEY AUTOINCREMENT,
			name    TEXT    NOT NULL,
			user_id INTEGER,
			UNIQUE (user_id, name)
		)`,
		`CREATE TABLE IF NOT EXISTS game_vibes (
			game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
			vibe_id INTEGER NOT NULL REFERENCES vibes(id) ON DELETE CASCADE,
			PRIMARY KEY (game_id, vibe_id)
		)`,
		// New collections tables (replaces vibes with richer semantics).
		`CREATE TABLE IF NOT EXISTS collections (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			name        TEXT    NOT NULL,
			description TEXT    NOT NULL DEFAULT '',
			created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE (user_id, name)
		)`,
		`CREATE TABLE IF NOT EXISTS collection_games (
			collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
			game_id       INTEGER NOT NULL REFERENCES games(id)       ON DELETE CASCADE,
			added_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (collection_id, game_id)
		)`,
		// Normalized category and mechanic tables for filtering.
		`CREATE TABLE IF NOT EXISTS categories (
			id   INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL UNIQUE
		)`,
		`CREATE TABLE IF NOT EXISTS game_categories (
			game_id     INTEGER NOT NULL REFERENCES games(id)      ON DELETE CASCADE,
			category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
			PRIMARY KEY (game_id, category_id)
		)`,
		`CREATE TABLE IF NOT EXISTS mechanics (
			id   INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL UNIQUE
		)`,
		`CREATE TABLE IF NOT EXISTS game_mechanics (
			game_id     INTEGER NOT NULL REFERENCES games(id)    ON DELETE CASCADE,
			mechanic_id INTEGER NOT NULL REFERENCES mechanics(id) ON DELETE CASCADE,
			PRIMARY KEY (game_id, mechanic_id)
		)`,
		`CREATE TABLE IF NOT EXISTS users (
			id               INTEGER  PRIMARY KEY AUTOINCREMENT,
			username         TEXT     NOT NULL UNIQUE,
			bgg_username     TEXT     NOT NULL DEFAULT '',
			password_hash    TEXT     NOT NULL DEFAULT '',
			email            TEXT     NOT NULL DEFAULT '',
			created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			last_sync_at     DATETIME,
			sync_count_today INTEGER  NOT NULL DEFAULT 0,
			sync_date        TEXT     NOT NULL DEFAULT '',
			is_admin         INTEGER  NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS sessions (
			token      TEXT PRIMARY KEY,
			user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			expires_at DATETIME NOT NULL,
			kind       TEXT     NOT NULL DEFAULT 'session'
		)`,
	}

	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return err
		}
	}

	// Additive column migrations (idempotent — SQLite ignores duplicate columns).
	addCols := []string{
		"ALTER TABLE games ADD COLUMN types               TEXT    NOT NULL DEFAULT ''",
		"ALTER TABLE games ADD COLUMN weight              REAL    NOT NULL DEFAULT 0.0",
		"ALTER TABLE games ADD COLUMN rating              REAL    NOT NULL DEFAULT 0.0",
		"ALTER TABLE games ADD COLUMN language_dependence INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE games ADD COLUMN recommended_players TEXT    NOT NULL DEFAULT ''",
		"ALTER TABLE games ADD COLUMN user_id             INTEGER REFERENCES users(id)",
		"ALTER TABLE vibes ADD COLUMN user_id             INTEGER REFERENCES users(id)",
		"ALTER TABLE sessions ADD COLUMN kind             TEXT    NOT NULL DEFAULT 'session'",
		"ALTER TABLE users ADD COLUMN is_admin            INTEGER NOT NULL DEFAULT 0",
		"ALTER TABLE users ADD COLUMN password_hash       TEXT    NOT NULL DEFAULT ''",
		"ALTER TABLE users ADD COLUMN username            TEXT    NOT NULL DEFAULT ''",
		"ALTER TABLE users ADD COLUMN email               TEXT    NOT NULL DEFAULT ''",
	}
	for _, s := range addCols {
		_, _ = db.Exec(s) // ignore "duplicate column" errors
	}

	// Populate username from bgg_username for legacy rows.
	_, _ = db.Exec("UPDATE users SET username = bgg_username WHERE username = ''")
	_, _ = db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE username != ''")
	_, _ = db.Exec("DROP INDEX IF EXISTS idx_users_bgg_username")

	if err := migratePerUserConstraints(db); err != nil {
		return err
	}

	// One-time migration: copy vibes → collections and game_vibes → collection_games.
	if err := migrateVibesToCollections(db); err != nil {
		return err
	}

	// FTS5 virtual table.
	if _, err := db.Exec(`
		CREATE VIRTUAL TABLE IF NOT EXISTS games_fts
		USING fts5(name, description, content=games, content_rowid=id)
	`); err != nil {
		return err
	}
	ftsTriggers := []string{
		`CREATE TRIGGER IF NOT EXISTS games_fts_insert AFTER INSERT ON games BEGIN
			INSERT INTO games_fts(rowid, name, description) VALUES (new.id, new.name, new.description);
		END`,
		`CREATE TRIGGER IF NOT EXISTS games_fts_delete AFTER DELETE ON games BEGIN
			INSERT INTO games_fts(games_fts, rowid, name, description)
			VALUES ('delete', old.id, old.name, old.description);
		END`,
		`CREATE TRIGGER IF NOT EXISTS games_fts_update AFTER UPDATE ON games BEGIN
			INSERT INTO games_fts(games_fts, rowid, name, description)
			VALUES ('delete', old.id, old.name, old.description);
			INSERT INTO games_fts(rowid, name, description) VALUES (new.id, new.name, new.description);
		END`,
	}
	for _, t := range ftsTriggers {
		if _, err := db.Exec(t); err != nil {
			return err
		}
	}

	// Rebuild FTS once on first run to index rows that predate the virtual table.
	rebuilt := getConfig(db, "fts_rebuilt")
	if rebuilt == "" {
		if _, err := db.Exec("INSERT INTO games_fts(games_fts) VALUES ('rebuild')"); err != nil {
			return err
		}
		if err := setConfig(db, "fts_rebuilt", "1"); err != nil {
			return err
		}
	}
	return nil
}

// migrateVibesToCollections copies existing vibes and game_vibes rows into the
// new collections and collection_games tables. It is idempotent — it only runs
// when the config flag "collections_migrated" is absent.
func migrateVibesToCollections(db *sql.DB) error {
	if getConfig(db, "collections_migrated") != "" {
		return nil
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Copy vibes → collections (INSERT OR IGNORE preserves idempotency).
	_, err = tx.Exec(`
		INSERT OR IGNORE INTO collections (id, user_id, name)
		SELECT v.id, v.user_id, v.name
		FROM vibes v
		WHERE v.user_id IS NOT NULL
	`)
	if err != nil {
		return fmt.Errorf("migrate vibes: %w", err)
	}

	// Copy game_vibes → collection_games.
	_, err = tx.Exec(`
		INSERT OR IGNORE INTO collection_games (collection_id, game_id)
		SELECT vibe_id, game_id FROM game_vibes
	`)
	if err != nil {
		return fmt.Errorf("migrate game_vibes: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return err
	}
	return setConfig(db, "collections_migrated", "1")
}

func migratePerUserConstraints(db *sql.DB) error {
	gamesNeedsMigration, err := hasSingleColumnUniqueIndex(db, "games", "bgg_id")
	if err != nil {
		return err
	}
	if gamesNeedsMigration {
		if err := migrateGamesTableForPerUserUniqueness(db); err != nil {
			return err
		}
	}

	vibesNeedsMigration, err := hasSingleColumnUniqueIndex(db, "vibes", "name")
	if err != nil {
		return err
	}
	if vibesNeedsMigration {
		if err := migrateVibesTableForPerUserUniqueness(db); err != nil {
			return err
		}
	}
	return nil
}

func hasSingleColumnUniqueIndex(db *sql.DB, table, column string) (bool, error) {
	rows, err := db.Query("PRAGMA index_list(" + table + ")")
	if err != nil {
		return false, err
	}
	defer rows.Close()

	for rows.Next() {
		var seq, unique, partial int
		var name, origin string
		if err := rows.Scan(&seq, &name, &unique, &origin, &partial); err != nil {
			return false, err
		}
		if unique == 0 {
			continue
		}
		infoRows, err := db.Query("PRAGMA index_info(" + quoteName(name) + ")")
		if err != nil {
			return false, err
		}
		var cols []string
		for infoRows.Next() {
			var seqno, cid int
			var col string
			if err := infoRows.Scan(&seqno, &cid, &col); err != nil {
				infoRows.Close()
				return false, err
			}
			cols = append(cols, col)
		}
		infoRows.Close()
		if infoRows.Err() != nil {
			return false, infoRows.Err()
		}
		if len(cols) == 1 && cols[0] == column {
			return true, nil
		}
	}
	return false, rows.Err()
}

func quoteName(name string) string {
	return "'" + strings.ReplaceAll(name, "'", "''") + "'"
}

func migrateGamesTableForPerUserUniqueness(db *sql.DB) error {
	for _, s := range []string{
		"DROP TRIGGER IF EXISTS games_fts_insert",
		"DROP TRIGGER IF EXISTS games_fts_delete",
		"DROP TRIGGER IF EXISTS games_fts_update",
		"DROP TABLE IF EXISTS games_fts",
	} {
		if _, err := db.Exec(s); err != nil {
			return err
		}
	}

	_, _ = db.Exec("PRAGMA foreign_keys = OFF")
	defer db.Exec("PRAGMA foreign_keys = ON")

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`
		CREATE TABLE games_new (
			id                  INTEGER PRIMARY KEY AUTOINCREMENT,
			bgg_id              INTEGER NOT NULL,
			name                TEXT    NOT NULL,
			description         TEXT    NOT NULL DEFAULT '',
			year_published      INTEGER NOT NULL DEFAULT 0,
			image               TEXT    NOT NULL DEFAULT '',
			thumbnail           TEXT    NOT NULL DEFAULT '',
			min_players         INTEGER NOT NULL DEFAULT 1,
			max_players         INTEGER NOT NULL DEFAULT 4,
			play_time           INTEGER NOT NULL DEFAULT 30,
			categories          TEXT    NOT NULL DEFAULT '',
			mechanics           TEXT    NOT NULL DEFAULT '',
			rules_url           TEXT    NOT NULL DEFAULT '',
			types               TEXT    NOT NULL DEFAULT '',
			weight              REAL    NOT NULL DEFAULT 0.0,
			rating              REAL    NOT NULL DEFAULT 0.0,
			language_dependence INTEGER NOT NULL DEFAULT 0,
			recommended_players TEXT    NOT NULL DEFAULT '',
			user_id             INTEGER,
			UNIQUE (user_id, bgg_id)
		)
	`); err != nil {
		return err
	}

	if _, err := tx.Exec(`
		INSERT INTO games_new (
			id, bgg_id, name, description, year_published, image, thumbnail,
			min_players, max_players, play_time, categories, mechanics,
			rules_url, types, weight, rating, language_dependence, recommended_players, user_id
		)
		SELECT
			id, bgg_id, name, description, year_published, image, thumbnail,
			min_players, max_players, play_time, categories, mechanics,
			rules_url,
			COALESCE(types, ''), COALESCE(weight, 0.0),
			COALESCE(rating, 0.0), COALESCE(language_dependence, 0),
			COALESCE(recommended_players, ''), user_id
		FROM games
	`); err != nil {
		return err
	}

	if _, err := tx.Exec("DROP TABLE games"); err != nil {
		return err
	}
	if _, err := tx.Exec("ALTER TABLE games_new RENAME TO games"); err != nil {
		return err
	}
	return tx.Commit()
}

func migrateVibesTableForPerUserUniqueness(db *sql.DB) error {
	_, _ = db.Exec("PRAGMA foreign_keys = OFF")
	defer db.Exec("PRAGMA foreign_keys = ON")

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`
		CREATE TABLE vibes_new (
			id      INTEGER PRIMARY KEY AUTOINCREMENT,
			name    TEXT NOT NULL,
			user_id INTEGER,
			UNIQUE (user_id, name)
		)
	`); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		INSERT INTO vibes_new (id, name, user_id)
		SELECT id, name, user_id FROM vibes
	`); err != nil {
		return err
	}
	if _, err := tx.Exec("DROP TABLE vibes"); err != nil {
		return err
	}
	if _, err := tx.Exec("ALTER TABLE vibes_new RENAME TO vibes"); err != nil {
		return err
	}
	return tx.Commit()
}

func migrateTestUser(db *sql.DB) error {
	testUser := strings.TrimSpace(os.Getenv("TEST_USER"))
	if testUser == "" {
		return nil
	}
	testPass := os.Getenv("TEST_PASSWORD")
	if testPass == "" {
		testPass = "testpass123"
	}

	// Check if test user already exists
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM users WHERE username = ?", testUser).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil // Already exists
	}

	// Create test user
	hash, err := hashPassword(testPass)
	if err != nil {
		return err
	}

	_, err = db.Exec(
		"INSERT INTO users (username, bgg_username, password_hash, email, is_admin) VALUES (?, ?, ?, ?, ?)",
		testUser, testUser, hash, testUser+"@test.com", 0,
	)
	return err
}

func hashPassword(password string) (string, error) {
	salt := make([]byte, argon2idSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := argon2.IDKey([]byte(password), salt, argon2idTime, argon2idMemory, argon2idParallelism, argon2idKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version,
		argon2idMemory, argon2idTime, argon2idParallelism,
		hex.EncodeToString(salt),
		hex.EncodeToString(hash),
	), nil
}

// migrateUserData assigns orphaned games/vibes (pre-multi-user) to the
// bgg_username stored in config. One-time, idempotent.
func migrateUserData(db *sql.DB) error {
	var orphaned int
	if err := db.QueryRow("SELECT COUNT(*) FROM games WHERE user_id IS NULL").Scan(&orphaned); err != nil || orphaned == 0 {
		return err
	}
	username := getConfig(db, "bgg_username")
	if username == "" {
		return nil
	}

	var userID int64
	err := db.QueryRow("SELECT id FROM users WHERE bgg_username = ?", username).Scan(&userID)
	if errors.Is(err, sql.ErrNoRows) {
		// Create a placeholder user for legacy data.
		res, insertErr := db.Exec(
			"INSERT INTO users (username, bgg_username, password_hash) VALUES (?, ?, ?)",
			username, username, "",
		)
		if insertErr != nil {
			return insertErr
		}
		userID, _ = res.LastInsertId()
	} else if err != nil {
		return err
	}

	if _, err := db.Exec("UPDATE games SET user_id = ? WHERE user_id IS NULL", userID); err != nil {
		return err
	}
	_, err = db.Exec("UPDATE vibes SET user_id = ? WHERE user_id IS NULL", userID)
	return err
}

// getConfig returns a config value, or "" when the key is absent.
func getConfig(db *sql.DB, key string) string {
	var v string
	_ = db.QueryRow("SELECT value FROM config WHERE key = ?", key).Scan(&v)
	return v
}

// setConfig upserts a key-value pair in the config table.
func setConfig(db *sql.DB, key, value string) error {
	_, err := db.Exec(
		"INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?",
		key, value, value,
	)
	return err
}

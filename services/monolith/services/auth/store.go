package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/LuisMedinaG/mbgc/services/monolith/shared/apierr"

	"golang.org/x/crypto/argon2"
)

// Store handles all user and session database operations.
type Store struct{ db *sql.DB }

// NewStore wraps the shared DB connection.
func NewStore(db *sql.DB) *Store { return &Store{db: db} }

// ── Users ─────────────────────────────────────────────────────────────────────

// RegisterUser creates a new user and returns their ID.
func (s *Store) RegisterUser(username, password, bggUsername, email string) (int64, error) {
	hash, err := hashPassword(password)
	if err != nil {
		return 0, err
	}
	res, err := s.db.Exec(
		"INSERT INTO users (username, bgg_username, password_hash, email, is_admin) VALUES (?, ?, ?, ?, 0)",
		username, bggUsername, hash, email,
	)
	if err != nil {
		if apierr.IsDuplicate(err) {
			return 0, apierr.ErrDuplicate
		}
		return 0, err
	}
	return res.LastInsertId()
}

// AuthenticateUser verifies credentials and returns the user ID on success.
// Legacy SHA-256 hashes are transparently upgraded to argon2id.
func (s *Store) AuthenticateUser(username, password string) (int64, error) {
	var id int64
	var hash string
	err := s.db.QueryRow(
		"SELECT id, password_hash FROM users WHERE username = ?", username,
	).Scan(&id, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, errors.New("invalid username or password")
	}
	if err != nil {
		return 0, err
	}
	ok, legacy := checkPasswordHash(password, hash)
	if !ok {
		return 0, errors.New("invalid username or password")
	}
	if legacy {
		if upgraded, hashErr := hashPassword(password); hashErr == nil {
			_, _ = s.db.Exec("UPDATE users SET password_hash = ? WHERE id = ?", upgraded, id)
		}
	}
	return id, nil
}

// ChangePassword verifies currentPassword then replaces the hash.
func (s *Store) ChangePassword(userID int64, currentPassword, newPassword string) error {
	var hash string
	if err := s.db.QueryRow("SELECT password_hash FROM users WHERE id = ?", userID).Scan(&hash); err != nil {
		return errors.New("user not found")
	}
	if ok, _ := checkPasswordHash(currentPassword, hash); !ok {
		return apierr.ErrWrongPassword
	}
	newHash, err := hashPassword(newPassword)
	if err != nil {
		return err
	}
	_, err = s.db.Exec("UPDATE users SET password_hash = ? WHERE id = ?", newHash, userID)
	return err
}

// GetUserInfo returns the username and admin flag for a user ID.
func (s *Store) GetUserInfo(userID int64) (username string, isAdmin bool, err error) {
	var isAdminInt int
	err = s.db.QueryRow(
		"SELECT username, is_admin FROM users WHERE id = ?", userID,
	).Scan(&username, &isAdminInt)
	return username, isAdminInt == 1, err
}

// GetBGGUsername returns the BGG username for a user.
func (s *Store) GetBGGUsername(userID int64) (string, error) {
	var v string
	err := s.db.QueryRow("SELECT bgg_username FROM users WHERE id = ?", userID).Scan(&v)
	return v, err
}

// SetBGGUsername updates the BGG username for a user.
func (s *Store) SetBGGUsername(userID int64, bggUsername string) error {
	_, err := s.db.Exec("UPDATE users SET bgg_username = ? WHERE id = ?", bggUsername, userID)
	return err
}

// CanSync reports whether the user has remaining sync quota for today.
func (s *Store) CanSync(userID int64, limit int) (bool, error) {
	today := time.Now().Format("2006-01-02")
	var syncDate string
	var count int
	err := s.db.QueryRow(
		"SELECT sync_date, sync_count_today FROM users WHERE id = ?", userID,
	).Scan(&syncDate, &count)
	if err != nil {
		return false, err
	}
	return syncDate != today || count < limit, nil
}

// RecordSync increments the user's daily sync counter.
func (s *Store) RecordSync(userID int64) error {
	today := time.Now().Format("2006-01-02")
	_, err := s.db.Exec(`
		UPDATE users SET
			last_sync_at     = CURRENT_TIMESTAMP,
			sync_count_today = CASE WHEN sync_date = ? THEN sync_count_today + 1 ELSE 1 END,
			sync_date        = ?
		WHERE id = ?`, today, today, userID)
	return err
}

// ── Sessions ──────────────────────────────────────────────────────────────────

func (s *Store) createToken(userID int64, kind string) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)
	expires := time.Now().Add(30 * 24 * time.Hour).UTC().Format(time.RFC3339)
	_, err := s.db.Exec(
		"INSERT INTO sessions (token, user_id, expires_at, kind) VALUES (?, ?, ?, ?)",
		token, userID, expires, kind,
	)
	return token, err
}

// CreateSession creates a browser session token.
func (s *Store) CreateSession(userID int64) (string, error) {
	return s.createToken(userID, "")
}

// CreateAPIRefreshToken creates a long-lived API refresh token.
func (s *Store) CreateAPIRefreshToken(userID int64) (string, error) {
	return s.createToken(userID, "api")
}

func (s *Store) validateToken(token, kind, notFoundMsg string) (int64, string, bool, error) {
	var userID, isAdminInt int64
	var username, expiresAt string
	query := `SELECT s.user_id, u.username, s.expires_at, u.is_admin
		FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?`
	args := []any{token}
	if kind != "" {
		query += " AND s.kind = ?"
		args = append(args, kind)
	}
	err := s.db.QueryRow(query, args...).Scan(&userID, &username, &expiresAt, &isAdminInt)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, "", false, errors.New(notFoundMsg)
	}
	if err != nil {
		return 0, "", false, err
	}
	exp, err := time.Parse(time.RFC3339, expiresAt)
	if err != nil || time.Now().After(exp) {
		return 0, "", false, errors.New(notFoundMsg)
	}
	return userID, username, isAdminInt == 1, nil
}

// ValidateSession checks that a browser session token is valid and unexpired.
func (s *Store) ValidateSession(token string) (int64, string, bool, error) {
	return s.validateToken(token, "", "session not found")
}

// ValidateAPIRefreshToken checks that an API refresh token is valid and unexpired.
func (s *Store) ValidateAPIRefreshToken(token string) (int64, string, bool, error) {
	return s.validateToken(token, "api", "invalid or expired refresh token")
}

// DeleteAPIRefreshToken removes a single API refresh token (logout).
func (s *Store) DeleteAPIRefreshToken(token string) error {
	_, err := s.db.Exec("DELETE FROM sessions WHERE token = ? AND kind = 'api'", token)
	return err
}

// DeleteExpiredSessions removes all expired sessions.
func (s *Store) DeleteExpiredSessions() error {
	_, err := s.db.Exec(
		"DELETE FROM sessions WHERE expires_at < ?",
		time.Now().UTC().Format(time.RFC3339),
	)
	return err
}

// ── Password hashing ──────────────────────────────────────────────────────────

const (
	argon2idMemory      = 64 * 1024
	argon2idTime        = 1
	argon2idParallelism = 4
	argon2idKeyLen      = 32
	argon2idSaltLen     = 16

	sha256IterationsV2    = 120000
	sha256HashVersion     = 2
	sha256HashBytesLength = 32
)

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

func checkPasswordHash(password, hash string) (match bool, legacy bool) {
	if strings.HasPrefix(hash, "$argon2id$") {
		return verifyArgon2idHash(password, hash), false
	}
	if strings.HasPrefix(hash, "$sha256$") {
		return verifySHA256V2Hash(password, hash), true
	}
	return verifyLegacySHA256Hash(password, hash), true
}

func verifyArgon2idHash(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}
	var memory, timeVal uint32
	var parallelism uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &timeVal, &parallelism); err != nil {
		return false
	}
	salt, err := hex.DecodeString(parts[4])
	if err != nil {
		return false
	}
	orig, err := hex.DecodeString(parts[5])
	if err != nil || len(orig) == 0 {
		return false
	}
	computed := argon2.IDKey([]byte(password), salt, timeVal, memory, parallelism, uint32(len(orig)))
	return subtle.ConstantTimeCompare(orig, computed) == 1
}

func verifyLegacySHA256Hash(password, hash string) bool {
	parts := strings.Split(hash, ":")
	if len(parts) != 2 {
		return false
	}
	salt, err := hex.DecodeString(parts[0])
	if err != nil {
		return false
	}
	orig, err := hex.DecodeString(parts[1])
	if err != nil {
		return false
	}
	h := sha256.New()
	h.Write(salt)
	h.Write([]byte(password))
	return subtle.ConstantTimeCompare(orig, h.Sum(nil)) == 1
}

func verifySHA256V2Hash(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "sha256" {
		return false
	}
	var version, iterations int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != sha256HashVersion {
		return false
	}
	if _, err := fmt.Sscanf(parts[3], "i=%d", &iterations); err != nil || iterations <= 0 {
		return false
	}
	salt, err := hex.DecodeString(parts[4])
	if err != nil {
		return false
	}
	orig, err := hex.DecodeString(parts[5])
	if err != nil || len(orig) != sha256HashBytesLength {
		return false
	}
	computed := iterativeSHA256([]byte(password), salt, iterations)
	return subtle.ConstantTimeCompare(orig, computed) == 1
}

func iterativeSHA256(password, salt []byte, iterations int) []byte {
	h := sha256.New()
	h.Write(salt)
	h.Write(password)
	sum := h.Sum(nil)
	for i := 1; i < iterations; i++ {
		h.Reset()
		h.Write(sum)
		sum = h.Sum(nil)
	}
	return sum
}

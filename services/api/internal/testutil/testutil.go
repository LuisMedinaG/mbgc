package testutil

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/LuisMedinaG/mbgc/services/api/internal/httpx"
	migrations "github.com/LuisMedinaG/mbgc/services/api/migrations"
)

const TestUserID = "test-user-id"

// NewAuthRequest builds an authenticated request with the default test user ID.
func NewAuthRequest(t *testing.T, method, path, body string) *http.Request {
	return NewAuthRequestAs(t, method, path, body, TestUserID, false)
}

// NewAuthRequestAs builds an authenticated request with a specific user ID and admin flag.
func NewAuthRequestAs(t *testing.T, method, path, body, userID string, isAdmin bool) *http.Request {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), userID, "testuser", isAdmin)
	return r.WithContext(ctx)
}

// NewAnonRequest builds an unauthenticated request.
func NewAnonRequest(t *testing.T, method, path, body string) *http.Request {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	return r
}

// DecodeJSON unmarshals the recorder body into T, failing the test on error.
func DecodeJSON[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	var result T
	if err := json.NewDecoder(w.Body).Decode(&result); err != nil {
		t.Fatalf("decode JSON: %v", err)
	}
	return result
}

// AssertStatus fails if the recorder status != want.
func AssertStatus(t *testing.T, w *httptest.ResponseRecorder, want int) {
	if w.Code != want {
		t.Errorf("expected status %d, got %d", want, w.Code)
	}
}

// CaptureSlog swaps slog.Default to a JSON handler writing to a buffer for
// the duration of the test, then restores the previous default.
func CaptureSlog(t *testing.T) *bytes.Buffer {
	t.Helper()
	buf := &bytes.Buffer{}
	prev := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(buf, &slog.HandlerOptions{Level: slog.LevelInfo})))
	t.Cleanup(func() { slog.SetDefault(prev) })
	return buf
}

// DecodeLogLines parses every JSON line in buf.
func DecodeLogLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimRight(buf.String(), "\n"), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("failed to parse log line %q: %v", line, err)
		}
		out = append(out, m)
	}
	return out
}

var migrateOnce sync.Once

// NewTestDB connects to DATABASE_URL, migrating it once per test binary run,
// and returns a pool with cleanup registered on t. Skips the test if
// DATABASE_URL is unset (no Postgres available, e.g. plain `go test ./...`
// without the CI service container or local Supabase running).
func NewTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		t.Skip("DATABASE_URL not set, skipping DB-backed test")
	}

	migrateOnce.Do(func() {
		db, err := sql.Open("pgx", url)
		if err != nil {
			t.Fatalf("open db for migrations: %v", err)
		}
		defer db.Close()
		src, err := iofs.New(migrations.FS, ".")
		if err != nil {
			t.Fatalf("migration source: %v", err)
		}
		driver, err := postgres.WithInstance(db, &postgres.Config{})
		if err != nil {
			t.Fatalf("migration driver: %v", err)
		}
		m, err := migrate.NewWithInstance("iofs", src, "postgres", driver)
		if err != nil {
			t.Fatalf("migrate init: %v", err)
		}
		defer m.Close()
		if err := m.Up(); err != nil && err != migrate.ErrNoChange {
			t.Fatalf("migrate up: %v", err)
		}
	})

	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatalf("connect pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

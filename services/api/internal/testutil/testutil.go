package testutil

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
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

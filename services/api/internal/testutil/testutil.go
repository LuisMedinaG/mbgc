package testutil

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

const TestUserID = "test-user-id"

// NewAuthRequest builds an authenticated httptest.Request with userID in context.
func NewAuthRequest(t *testing.T, method, path, body string) *http.Request {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), TestUserID, "testuser", false)
	return r.WithContext(ctx)
}

// NewAnonRequest builds an unauthenticated httptest.Request.
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

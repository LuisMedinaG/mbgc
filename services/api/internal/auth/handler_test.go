package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/services/api/internal/httpx"
)

// --- login ---

func TestLogin_InvalidBody(t *testing.T) {
	h := NewHandler(nil, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader("bad json"))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestLogin_MissingFields(t *testing.T) {
	h := NewHandler(nil, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":""}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// ref: auth.LOGIN.1 — proxies to Supabase token endpoint
// ref: auth.LOGIN.1 — accepts email or username format
func TestLogin_SupabaseFailure(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer supa.Close()

	h := NewHandler(nil, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"u@example.com","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestLogin_Success(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token":  "at-123",
			"refresh_token": "rt-456",
			"expires_in":    3600,
		})
	}))
	defer supa.Close()

	h := NewHandler(nil, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"u@example.com","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp httpx.Response[tokenData]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Data.AccessToken != "at-123" {
		t.Fatalf("expected at-123, got %s", resp.Data.AccessToken)
	}
}

func TestLogin_SupabaseUnreachable(t *testing.T) {
	h := NewHandler(nil, "http://127.0.0.1:1", "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"u@example.com","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}

// fakeStore implements userStore for handler tests without a database.
type fakeStore struct {
	email string
	err   error
}

func (f fakeStore) EmailByUsername(_ context.Context, _ string) (string, error) {
	return f.email, f.err
}

func (f fakeStore) EmailByUserID(_ context.Context, _ string) (string, error) {
	return f.email, f.err
}

// ref: auth.LOGIN.1 — accepts username, resolves to email via indexed store lookup
func TestLogin_WithUsername(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"access_token":  "at-123",
			"refresh_token": "rt-456",
			"expires_in":    3600,
		})
	}))
	defer supa.Close()

	h := NewHandler(fakeStore{email: "test@example.com"}, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"testuser","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp httpx.Response[tokenData]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Data.AccessToken != "at-123" {
		t.Fatalf("expected at-123, got %s", resp.Data.AccessToken)
	}
}

// ref: auth.LOGIN.3 — unknown username returns generic error (no enumeration)
func TestLogin_UnknownUsername(t *testing.T) {
	h := NewHandler(fakeStore{err: errors.New("no rows")}, "http://unused", "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"ghost","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

// --- refresh ---

func TestRefresh_MissingToken(t *testing.T) {
	h := NewHandler(nil, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/refresh", strings.NewReader(`{}`))
	r.Header.Set("Content-Type", "application/json")
	h.refresh(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// ref: auth.REFRESH.1 — proxies to Supabase refresh token endpoint
func TestRefresh_SupabaseFailure(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer supa.Close()

	h := NewHandler(nil, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/refresh", strings.NewReader(`{"refresh_token":"rt"}`))
	r.Header.Set("Content-Type", "application/json")
	h.refresh(w, r)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRefresh_Success(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token":  "new-at",
			"refresh_token": "new-rt",
			"expires_in":    3600,
		})
	}))
	defer supa.Close()

	h := NewHandler(nil, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/refresh", strings.NewReader(`{"refresh_token":"rt"}`))
	r.Header.Set("Content-Type", "application/json")
	h.refresh(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

// --- logout ---

// ref: auth.LOGOUT.1 — proxies to Supabase logout endpoint
func TestLogout_AlwaysSucceeds(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer supa.Close()

	h := NewHandler(nil, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/logout", strings.NewReader(`{"refresh_token":"rt"}`))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Authorization", "Bearer at-123")
	h.logout(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

func TestLogout_WithoutToken(t *testing.T) {
	h := NewHandler(nil, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/logout", strings.NewReader(`{}`))
	r.Header.Set("Content-Type", "application/json")
	h.logout(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

// --- ping ---

func TestPing_WithUser(t *testing.T) {
	h := NewHandler(nil, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
	r = r.WithContext(ctx)
	h.ping(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp httpx.Response[map[string]interface{}]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	pong, _ := resp.Data["pong"].(bool)
	username, _ := resp.Data["username"].(string)
	if !pong || username != "alice" {
		t.Fatalf("expected pong=true, username=alice, got %+v", resp.Data)
	}
}

func TestPing_NoUser(t *testing.T) {
	h := NewHandler(nil, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	h.ping(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp httpx.Response[map[string]interface{}]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	pong, _ := resp.Data["pong"].(bool)
	username, _ := resp.Data["username"].(string)
	if !pong || username != "" {
		t.Fatalf("expected pong=true, username=\"\", got %+v", resp.Data)
	}
}

// --- changePassword ---

// ref: auth.CHANGE_PASSWORD.2 — missing fields returns 400
func TestChangePassword_MissingFields(t *testing.T) {
	h := NewHandler(fakeStore{email: "u@example.com"}, "", "", 	httpx.DefaultClient)
	cases := []string{
		`{}`,
		`{"current_password":"old"}`,
		`{"new_password":"newpass1"}`,
	}
	for _, body := range cases {
		w := httptest.NewRecorder()
		r := httptest.NewRequest("PUT", "/api/v1/auth/password", strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
		r = r.WithContext(ctx)
		h.changePassword(w, r)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("body %s: expected 400, got %d", body, w.Code)
		}
	}
}

// ref: auth.CHANGE_PASSWORD.2 — new password below minimum length returns 400
func TestChangePassword_ShortNewPassword(t *testing.T) {
	h := NewHandler(fakeStore{email: "u@example.com"}, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("PUT", "/api/v1/auth/password", strings.NewReader(`{"current_password":"oldpass1","new_password":"short"}`))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
	r = r.WithContext(ctx)
	h.changePassword(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// ref: auth.CHANGE_PASSWORD.1 — store error (user not found) returns 401
func TestChangePassword_StoreError(t *testing.T) {
	h := NewHandler(fakeStore{err: errors.New("no rows")}, "", "", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("PUT", "/api/v1/auth/password", strings.NewReader(`{"current_password":"oldpass1","new_password":"newpass1"}`))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
	r = r.WithContext(ctx)
	h.changePassword(w, r)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

// ref: auth.CHANGE_PASSWORD.1 — wrong current password returns 401, no internal detail
func TestChangePassword_WrongCurrentPassword(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer supa.Close()

	h := NewHandler(fakeStore{email: "u@example.com"}, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("PUT", "/api/v1/auth/password", strings.NewReader(`{"current_password":"wrongpass","new_password":"newpass99"}`))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Authorization", "Bearer valid-token")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
	r = r.WithContext(ctx)
	h.changePassword(w, r)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

// ref: auth.CHANGE_PASSWORD.1, auth.CHANGE_PASSWORD.3 — success returns 204
func TestChangePassword_Success(t *testing.T) {
	reqCount := 0
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqCount++
		if reqCount == 1 {
			// token grant — verify current password
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{"access_token": "at-ok"})
			return
		}
		// PUT /auth/v1/user — update password
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"id": "user-1"})
	}))
	defer supa.Close()

	h := NewHandler(fakeStore{email: "u@example.com"}, supa.URL, "fake-key", 	httpx.DefaultClient)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("PUT", "/api/v1/auth/password", strings.NewReader(`{"current_password":"oldpass1","new_password":"newpass99"}`))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Authorization", "Bearer valid-token")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
	r = r.WithContext(ctx)
	h.changePassword(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", w.Code, w.Body.String())
	}
	if reqCount != 2 {
		t.Fatalf("expected 2 Supabase calls, got %d", reqCount)
	}
}

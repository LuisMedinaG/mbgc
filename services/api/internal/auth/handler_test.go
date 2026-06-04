package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// --- login ---

func TestLogin_InvalidBody(t *testing.T) {
	h := NewHandler(nil, "", "")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader("bad json"))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestLogin_MissingFields(t *testing.T) {
	h := NewHandler(nil, "", "")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":""}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// ref: auth.LOGIN.1 — proxies to Supabase token endpoint
func TestLogin_SupabaseFailure(t *testing.T) {
	supa := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer supa.Close()

	h := NewHandler(nil, supa.URL, "fake-key")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"u","password":"p"}`))
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

	h := NewHandler(nil, supa.URL, "fake-key")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"u","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.Response[tokenData]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Data.AccessToken != "at-123" {
		t.Fatalf("expected at-123, got %s", resp.Data.AccessToken)
	}
}

func TestLogin_SupabaseUnreachable(t *testing.T) {
	h := NewHandler(nil, "http://127.0.0.1:1", "fake-key")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/auth/login", strings.NewReader(`{"username":"u","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	h.login(w, r)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}

// --- refresh ---

func TestRefresh_MissingToken(t *testing.T) {
	h := NewHandler(nil, "", "")
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

	h := NewHandler(nil, supa.URL, "fake-key")
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

	h := NewHandler(nil, supa.URL, "fake-key")
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

	h := NewHandler(nil, supa.URL, "fake-key")
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
	h := NewHandler(nil, "", "")
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
	h := NewHandler(nil, "", "")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "alice", false)
	r = r.WithContext(ctx)
	h.ping(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.Response[map[string]interface{}]
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
	h := NewHandler(nil, "", "")
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	h.ping(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.Response[map[string]interface{}]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	pong, _ := resp.Data["pong"].(bool)
	username, _ := resp.Data["username"].(string)
	if !pong || username != "" {
		t.Fatalf("expected pong=true, username=\"\", got %+v", resp.Data)
	}
}

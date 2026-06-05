package seed

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/services/api/internal/config"
)

func TestAdminUser_SkipsIfServiceRoleKeyEmpty(t *testing.T) {
	cfg := config.Config{
		ServiceRoleKey: "",
	}

	err := AdminUser(context.Background(), cfg, nil)
	if err == nil {
		t.Fatal("expected error when ServiceRoleKey is empty")
	}
	if !strings.Contains(err.Error(), "SUPABASE_SERVICE_ROLE_KEY") {
		t.Errorf("error should mention SUPABASE_SERVICE_ROLE_KEY, got: %v", err)
	}
}

func TestAdminUser_PropagatesAuthUserError(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:       "http://invalid-host:9999",
		ServiceRoleKey:    "test-key",
		SeedAdminEmail:    "admin@test.local",
		SeedAdminPassword: "password123",
	}

	err := AdminUser(context.Background(), cfg, nil)
	if err == nil {
		t.Fatal("expected error from unreachable Supabase")
	}
	if !strings.Contains(err.Error(), "auth user") {
		t.Errorf("error should mention 'auth user', got: %v", err)
	}
}

func TestEnsureAuthUser_CreatesNew(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:        "http://localhost:54321",
		ServiceRoleKey:     "test-key",
		SeedAdminEmail:     "admin@test.local",
		SeedAdminPassword:  "password123",
		SeedAdminUsername:  "admin_user",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		// Verify headers
		if got := r.Header.Get("Authorization"); !strings.Contains(got, "Bearer test-key") {
			t.Errorf("Authorization header: %q", got)
		}
		if got := r.Header.Get("apikey"); got != "test-key" {
			t.Errorf("apikey header: %q", got)
		}

		// Verify body
		var payload map[string]interface{}
		json.NewDecoder(r.Body).Decode(&payload)
		if payload["email"] != "admin@test.local" {
			t.Errorf("email: %v", payload["email"])
		}
		if payload["password"] != "password123" {
			t.Errorf("password mismatch")
		}
		if payload["email_confirm"] != true {
			t.Errorf("email_confirm should be true")
		}

		meta := payload["user_metadata"].(map[string]interface{})
		if meta["username"] != "admin_user" {
			t.Errorf("username in metadata: %v", meta)
		}

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"id": "new-user-id"})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	userID, err := ensureAuthUser(context.Background(), cfg)
	if err != nil {
		t.Fatalf("ensureAuthUser: %v", err)
	}
	if userID != "new-user-id" {
		t.Errorf("expected 'new-user-id', got %q", userID)
	}
}

func TestEnsureAuthUser_ReturnsExistingUserID(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:        "http://localhost:54321",
		ServiceRoleKey:     "test-key",
		SeedAdminEmail:     "admin@test.local",
		SeedAdminPassword:  "password123",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			// User already exists
			w.WriteHeader(http.StatusUnprocessableEntity)
			json.NewEncoder(w).Encode(map[string]string{
				"msg": "already exists",
			})
			return
		}

		if r.Method == http.MethodGet && strings.Contains(r.URL.Path, "/auth/v1/admin/users") {
			// Lookup returns the existing user
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"users": []map[string]string{
					{"id": "existing-user-id", "email": "admin@test.local"},
				},
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	userID, err := ensureAuthUser(context.Background(), cfg)
	if err != nil {
		t.Fatalf("ensureAuthUser: %v", err)
	}
	if userID != "existing-user-id" {
		t.Errorf("expected 'existing-user-id', got %q", userID)
	}
}

func TestEnsureAuthUser_ErrorOnHTTPFailure(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:        "http://localhost:54321",
		ServiceRoleKey:     "test-key",
		SeedAdminEmail:     "admin@test.local",
		SeedAdminPassword:  "password123",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"msg": "server error"})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	_, err := ensureAuthUser(context.Background(), cfg)
	if err == nil {
		t.Fatal("expected error from HTTP 500")
	}
	if !strings.Contains(err.Error(), "500") {
		t.Errorf("error should mention status code, got: %v", err)
	}
}

func TestEnsureAuthUser_WithoutUsername(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:        "http://localhost:54321",
		ServiceRoleKey:     "test-key",
		SeedAdminEmail:     "admin@test.local",
		SeedAdminPassword:  "password123",
		SeedAdminUsername:  "", // No username
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			var payload map[string]interface{}
			json.NewDecoder(r.Body).Decode(&payload)

			// user_metadata should not be present
			if _, exists := payload["user_metadata"]; exists {
				t.Error("user_metadata should not be included when username is empty")
			}

			w.WriteHeader(http.StatusCreated)
			json.NewEncoder(w).Encode(map[string]string{"id": "user-id"})
		}
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	_, err := ensureAuthUser(context.Background(), cfg)
	if err != nil {
		t.Fatalf("ensureAuthUser: %v", err)
	}
}

func TestEnsureAdminAppMetadata_Success(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:    "http://localhost:54321",
		ServiceRoleKey: "test-key",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		// Verify URL contains user ID
		if !strings.Contains(r.URL.Path, "user-123") {
			t.Errorf("URL should contain user ID, got: %s", r.URL.Path)
		}

		var update map[string]interface{}
		json.NewDecoder(r.Body).Decode(&update)
		if app := update["app_metadata"].(map[string]interface{}); app["is_admin"] != true {
			t.Error("is_admin should be true")
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	err := ensureAdminAppMetadata(context.Background(), cfg, "user-123")
	if err != nil {
		t.Fatalf("ensureAdminAppMetadata: %v", err)
	}
}

func TestEnsureAdminAppMetadata_WithUsername(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:       "http://localhost:54321",
		ServiceRoleKey:    "test-key",
		SeedAdminUsername: "admin_user",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var update map[string]interface{}
		json.NewDecoder(r.Body).Decode(&update)

		// Check user_metadata is included
		if user, exists := update["user_metadata"]; !exists {
			t.Error("user_metadata should be included when username is set")
		} else if user.(map[string]interface{})["username"] != "admin_user" {
			t.Error("username mismatch in metadata")
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	err := ensureAdminAppMetadata(context.Background(), cfg, "user-id")
	if err != nil {
		t.Fatalf("ensureAdminAppMetadata: %v", err)
	}
}

func TestEnsureAdminAppMetadata_ErrorOnHTTPFailure(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:    "http://localhost:54321",
		ServiceRoleKey: "test-key",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"msg": "invalid payload"})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	err := ensureAdminAppMetadata(context.Background(), cfg, "user-id")
	if err == nil {
		t.Fatal("expected error from HTTP 400")
	}
	if !strings.Contains(err.Error(), "400") {
		t.Errorf("error should mention status code, got: %v", err)
	}
}

func TestLookupAuthUserByEmail_Found(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:    "http://localhost:54321",
		ServiceRoleKey: "test-key",
		SeedAdminEmail: "admin@test.local",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify query param for pagination
		if !strings.Contains(r.URL.RawQuery, "per_page=1000") {
			t.Errorf("expected per_page=1000, got: %s", r.URL.RawQuery)
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"users": []map[string]string{
				{"id": "user-456", "email": "admin@test.local"},
				{"id": "user-789", "email": "other@test.local"},
			},
		})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	userID, err := lookupAuthUserByEmail(context.Background(), cfg)
	if err != nil {
		t.Fatalf("lookupAuthUserByEmail: %v", err)
	}
	if userID != "user-456" {
		t.Errorf("expected 'user-456', got %q", userID)
	}
}

func TestLookupAuthUserByEmail_CaseInsensitive(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:    "http://localhost:54321",
		ServiceRoleKey: "test-key",
		SeedAdminEmail: "Admin@Test.Local",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"users": []map[string]string{
				{"id": "user-id", "email": "admin@test.local"},
			},
		})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	userID, err := lookupAuthUserByEmail(context.Background(), cfg)
	if err != nil {
		t.Fatalf("lookupAuthUserByEmail: %v", err)
	}
	if userID != "user-id" {
		t.Errorf("lookup should be case-insensitive, got %q", userID)
	}
}

func TestLookupAuthUserByEmail_NotFound(t *testing.T) {
	cfg := config.Config{
		SupabaseURL:    "http://localhost:54321",
		ServiceRoleKey: "test-key",
		SeedAdminEmail: "nonexistent@test.local",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"users": []map[string]string{
				{"id": "user-id", "email": "other@test.local"},
			},
		})
	}))
	defer server.Close()

	cfg.SupabaseURL = server.URL

	_, err := lookupAuthUserByEmail(context.Background(), cfg)
	if err == nil {
		t.Fatal("expected error when user not found")
	}
	if !strings.Contains(err.Error(), "not found") {
		t.Errorf("error should say 'not found', got: %v", err)
	}
}


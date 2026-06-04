package jwt

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

const testSecret = "test-secret-key-for-hs256"
const testIssuer = "http://localhost/auth/v1"

func testVerifier(t *testing.T) *Verifier {
	t.Helper()
	kf := func(token *jwtlib.Token) (interface{}, error) {
		return []byte(testSecret), nil
	}
	return &Verifier{keyfunc: kf, issuer: testIssuer}
}

func signToken(claims jwtlib.Claims) string {
	token := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims)
	s, _ := token.SignedString([]byte(testSecret))
	return s
}

func validClaims(sub, email string, admin bool) *claims {
	meta := map[string]interface{}{}
	if admin {
		meta["is_admin"] = true
	}
	return &claims{
		RegisteredClaims: jwtlib.RegisteredClaims{
			Subject:   sub,
			Issuer:    testIssuer,
			Audience:  jwtlib.ClaimStrings{"authenticated"},
			ExpiresAt: jwtlib.NewNumericDate(time.Now().Add(time.Hour)),
			IssuedAt:  jwtlib.NewNumericDate(time.Now()),
		},
		Email:        email,
		Role:         "authenticated",
		AppMetadata:  meta,
		UserMetadata: map[string]interface{}{"username": "testuser"},
	}
}

func TestRequireAuth_NoHeader(t *testing.T) {
	v := testVerifier(t)
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	v.RequireAuth(inner).ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRequireAuth_MalformedHeader(t *testing.T) {
	v := testVerifier(t)
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Token xyz")
	v.RequireAuth(inner).ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRequireAuth_InvalidToken(t *testing.T) {
	v := testVerifier(t)
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Bearer not.a.valid.jwt")
	v.RequireAuth(inner).ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRequireAuth_ExpiredToken(t *testing.T) {
	v := testVerifier(t)
	c := validClaims("user-1", "test@test.com", false)
	c.ExpiresAt = jwtlib.NewNumericDate(time.Now().Add(-time.Hour))
	tok := signToken(c)

	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Bearer "+tok)
	v.RequireAuth(inner).ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRequireAuth_WrongIssuer(t *testing.T) {
	v := testVerifier(t)
	c := validClaims("user-1", "test@test.com", false)
	c.Issuer = "http://evil.com/auth/v1"
	tok := signToken(c)

	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Bearer "+tok)
	v.RequireAuth(inner).ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRequireAuth_WrongAudience(t *testing.T) {
	v := testVerifier(t)
	c := validClaims("user-1", "test@test.com", false)
	c.Audience = jwtlib.ClaimStrings{"service_role"}
	tok := signToken(c)

	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Bearer "+tok)
	v.RequireAuth(inner).ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRequireAuth_ValidToken(t *testing.T) {
	v := testVerifier(t)
	tok := signToken(validClaims("user-123", "alice@test.com", false))

	var gotUserID, gotUsername string
	var gotAdmin bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotUserID, _ = httpx.UserIDFromContext(r.Context())
		gotUsername = httpx.UsernameFromContext(r.Context())
		gotAdmin = httpx.IsAdminFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	})

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Bearer "+tok)
	v.RequireAuth(inner).ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if gotUserID != "user-123" {
		t.Fatalf("expected user-123, got %s", gotUserID)
	}
	if gotUsername != "testuser" {
		t.Fatalf("expected testuser, got %s", gotUsername)
	}
	if gotAdmin {
		t.Fatal("expected non-admin")
	}
}

func TestRequireAuth_AdminToken(t *testing.T) {
	v := testVerifier(t)
	tok := signToken(validClaims("admin-1", "admin@test.com", true))

	var gotAdmin bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAdmin = httpx.IsAdminFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	})

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	r.Header.Set("Authorization", "Bearer "+tok)
	v.RequireAuth(inner).ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !gotAdmin {
		t.Fatal("expected admin=true")
	}
}

func TestClaims_Username(t *testing.T) {
	c := &claims{
		Email:        "fallback@test.com",
		UserMetadata: map[string]interface{}{"username": "myhandle"},
	}
	if c.username() != "myhandle" {
		t.Fatalf("expected myhandle, got %s", c.username())
	}

	c2 := &claims{Email: "fallback@test.com"}
	if c2.username() != "fallback@test.com" {
		t.Fatalf("expected email fallback, got %s", c2.username())
	}

	c3 := &claims{Email: "fallback@test.com", UserMetadata: map[string]interface{}{"username": ""}}
	if c3.username() != "fallback@test.com" {
		t.Fatalf("expected email when username empty, got %s", c3.username())
	}
}

func TestClaims_IsAdmin(t *testing.T) {
	c := &claims{AppMetadata: map[string]interface{}{"is_admin": true}}
	if !c.isAdmin() {
		t.Fatal("expected true")
	}

	c2 := &claims{AppMetadata: map[string]interface{}{"is_admin": false}}
	if c2.isAdmin() {
		t.Fatal("expected false")
	}

	c3 := &claims{}
	if c3.isAdmin() {
		t.Fatal("expected false for nil metadata")
	}
}

func TestRequireAuth_ErrorResponseShape(t *testing.T) {
	v := testVerifier(t)
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/ping", nil)
	v.RequireAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})).ServeHTTP(w, r)

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)
	errObj, ok := resp["error"].(map[string]interface{})
	if !ok {
		t.Fatal("expected error object in response")
	}
	if errObj["code"] != "UNAUTHORIZED" {
		t.Fatalf("expected UNAUTHORIZED code, got %s", errObj["code"])
	}
}

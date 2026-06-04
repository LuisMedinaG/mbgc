package httpx

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

func errNotFound() error      { return apierr.ErrNotFound }
func errDuplicate() error     { return apierr.ErrDuplicate }
func errUnauthorized() error  { return apierr.ErrUnauthorized }
func errWrongPassword() error { return apierr.ErrWrongPassword }
func errForbidden() error     { return apierr.ErrForbidden }
func errRateLimit() error     { return apierr.ErrRateLimit }
func errBadRequest() error    { return apierr.ErrBadRequest }
func errValidation() error    { return apierr.ErrValidation }
func errUnknown() error       { return errors.New("something broke") }

func TestCORS_AllowedOrigin(t *testing.T) {
	mw := CORS([]string{"https://app.example.com"})
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := mw(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://app.example.com")
	handler.ServeHTTP(w, r)

	if w.Header().Get("Access-Control-Allow-Origin") != "https://app.example.com" {
		t.Fatalf("expected ACAO header, got %q", w.Header().Get("Access-Control-Allow-Origin"))
	}
	if w.Header().Get("Access-Control-Allow-Methods") == "" {
		t.Fatal("expected Allow-Methods header")
	}
	if w.Header().Get("Access-Control-Max-Age") != "86400" {
		t.Fatalf("expected Max-Age 86400, got %s", w.Header().Get("Access-Control-Max-Age"))
	}
}

func TestCORS_DisallowedOrigin(t *testing.T) {
	mw := CORS([]string{"https://app.example.com"})
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := mw(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://evil.com")
	handler.ServeHTTP(w, r)

	if w.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatalf("expected no ACAO header for disallowed origin, got %q", w.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestCORS_Preflight(t *testing.T) {
	mw := CORS([]string{"https://app.example.com"})
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called for OPTIONS")
	})
	handler := mw(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("OPTIONS", "/api/v1/games", nil)
	r.Header.Set("Origin", "https://app.example.com")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204 for preflight, got %d", w.Code)
	}
}

func TestCORS_NoOriginHeader(t *testing.T) {
	mw := CORS([]string{"https://app.example.com"})
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := mw(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	if w.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatal("expected no ACAO when no Origin header")
	}
}

func TestSecurityHeaders(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := SecurityHeaders(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	checks := map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "strict-origin-when-cross-origin",
	}
	for header, expected := range checks {
		if got := w.Header().Get(header); got != expected {
			t.Fatalf("expected %s=%q, got %q", header, expected, got)
		}
	}
	if w.Header().Get("Content-Security-Policy") == "" {
		t.Fatal("expected Content-Security-Policy header")
	}
}

func TestRecover_NoPanic(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := Recover(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestRecover_WithPanic(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("test panic")
	})
	handler := Recover(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)
	errObj, ok := resp["error"].(map[string]interface{})
	if !ok {
		t.Fatal("expected error object")
	}
	if errObj["code"] != "INTERNAL_ERROR" {
		t.Fatalf("expected INTERNAL_ERROR, got %s", errObj["code"])
	}
}

func TestRequestID_GeneratesWhenMissing(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := RequestIDFromContext(r.Context())
		if id == "" {
			t.Fatal("expected request ID in context")
		}
		w.WriteHeader(http.StatusOK)
	})
	handler := RequestID(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	if w.Header().Get("X-Request-ID") == "" {
		t.Fatal("expected X-Request-ID response header")
	}
}

func TestRequestID_PreservesExisting(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := RequestIDFromContext(r.Context())
		if id != "my-custom-id" {
			t.Fatalf("expected my-custom-id, got %s", id)
		}
		w.WriteHeader(http.StatusOK)
	})
	handler := RequestID(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("X-Request-ID", "my-custom-id")
	handler.ServeHTTP(w, r)

	if w.Header().Get("X-Request-ID") != "my-custom-id" {
		t.Fatalf("expected preserved ID, got %s", w.Header().Get("X-Request-ID"))
	}
}

func TestTrustGatewayHeaders(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID, ok := UserIDFromContext(r.Context())
		if !ok || userID != "user-abc" {
			t.Fatalf("expected user-abc, got %s (ok=%v)", userID, ok)
		}
		username := UsernameFromContext(r.Context())
		if username != "alice" {
			t.Fatalf("expected alice, got %s", username)
		}
		isAdmin := IsAdminFromContext(r.Context())
		if !isAdmin {
			t.Fatal("expected admin=true")
		}
		w.WriteHeader(http.StatusOK)
	})
	handler := TrustGatewayHeaders(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("X-User-ID", "user-abc")
	r.Header.Set("X-Username", "alice")
	r.Header.Set("X-Is-Admin", "true")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestTrustGatewayHeaders_NoHeaders(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, ok := UserIDFromContext(r.Context())
		if ok {
			t.Fatal("expected no user when no gateway headers")
		}
		w.WriteHeader(http.StatusOK)
	})
	handler := TrustGatewayHeaders(inner)

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestChain(t *testing.T) {
	var order []string
	mw := func(name string) func(http.Handler) http.Handler {
		return func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				order = append(order, name)
				next.ServeHTTP(w, r)
			})
		}
	}

	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		order = append(order, "handler")
		w.WriteHeader(http.StatusOK)
	})

	handler := Chain(inner, mw("first"), mw("second"), mw("third"))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	handler.ServeHTTP(w, r)

	expected := []string{"first", "second", "third", "handler"}
	if len(order) != len(expected) {
		t.Fatalf("expected %v, got %v", expected, order)
	}
	for i, v := range expected {
		if order[i] != v {
			t.Fatalf("position %d: expected %s, got %s", i, v, order[i])
		}
	}
}

func TestLogger(t *testing.T) {
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := Logger(RequestID(inner))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v1/games", nil)
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestContextAccessors(t *testing.T) {
	ctx := SetGatewayUser(t.Context(), "uid", "uname", true)

	uid, ok := UserIDFromContext(ctx)
	if !ok || uid != "uid" {
		t.Fatalf("UserID: expected uid, got %s", uid)
	}

	uname := UsernameFromContext(ctx)
	if uname != "uname" {
		t.Fatalf("Username: expected uname, got %s", uname)
	}

	if !IsAdminFromContext(ctx) {
		t.Fatal("IsAdmin: expected true")
	}

	emptyCtx := t.Context()
	_, ok = UserIDFromContext(emptyCtx)
	if ok {
		t.Fatal("expected no user in empty context")
	}
	if IsAdminFromContext(emptyCtx) {
		t.Fatal("expected false admin in empty context")
	}
	if UsernameFromContext(emptyCtx) != "" {
		t.Fatal("expected empty username in empty context")
	}
}

func TestWriteError_AllSentinels(t *testing.T) {
	cases := []struct {
		name   string
		err    error
		status int
	}{
		{"not found", errNotFound(), http.StatusNotFound},
		{"duplicate", errDuplicate(), http.StatusConflict},
		{"unauthorized", errUnauthorized(), http.StatusUnauthorized},
		{"wrong password", errWrongPassword(), http.StatusUnauthorized},
		{"forbidden", errForbidden(), http.StatusForbidden},
		{"rate limit", errRateLimit(), http.StatusTooManyRequests},
		{"bad request", errBadRequest(), http.StatusBadRequest},
		{"validation", errValidation(), http.StatusUnprocessableEntity},
		{"unknown", errUnknown(), http.StatusInternalServerError},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			WriteError(w, tc.err)
			if w.Code != tc.status {
				t.Fatalf("expected %d, got %d", tc.status, w.Code)
			}
			ct := w.Header().Get("Content-Type")
			if !strings.Contains(ct, "application/json") {
				t.Fatalf("expected JSON content-type, got %s", ct)
			}
		})
	}
}

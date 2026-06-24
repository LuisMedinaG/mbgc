package httpx

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// ref: api-layer.SEC.8 — CORS middleware validation
func TestCORS_AllowedOrigin(t *testing.T) {
	cors := CORS([]string{"https://example.com", "https://app.local"})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://example.com")
	handler.ServeHTTP(w, r)

	if w.Header().Get("Access-Control-Allow-Origin") != "https://example.com" {
		t.Fatalf("expected origin in response, got %q", w.Header().Get("Access-Control-Allow-Origin"))
	}
	if w.Header().Get("Access-Control-Allow-Credentials") != "true" {
		t.Fatalf("expected credentials header, got %q", w.Header().Get("Access-Control-Allow-Credentials"))
	}
}

func TestCORS_DisallowedOrigin(t *testing.T) {
	cors := CORS([]string{"https://example.com"})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://evil.com")
	handler.ServeHTTP(w, r)

	if w.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatalf("expected no CORS headers for disallowed origin, got %q", w.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestCORS_Preflight(t *testing.T) {
	cors := CORS([]string{"https://example.com"})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("OPTIONS", "/", nil)
	r.Header.Set("Origin", "https://example.com")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
	if w.Header().Get("Access-Control-Allow-Origin") != "https://example.com" {
		t.Fatalf("expected origin in response, got %q", w.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestCORS_VaryHeader(t *testing.T) {
	cors := CORS([]string{"https://example.com"})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://example.com")
	handler.ServeHTTP(w, r)

	if w.Header().Get("Vary") != "Origin" {
		t.Fatalf("expected Vary: Origin, got %q", w.Header().Get("Vary"))
	}
}

func TestCORS_AllowedMethods(t *testing.T) {
	cors := CORS([]string{"https://example.com"})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://example.com")
	handler.ServeHTTP(w, r)

	methods := w.Header().Get("Access-Control-Allow-Methods")
	if methods == "" {
		t.Fatal("expected Access-Control-Allow-Methods header")
	}
	if methods != "GET, POST, PUT, PATCH, DELETE, OPTIONS" {
		t.Fatalf("unexpected methods: %q", methods)
	}
}

func TestCORS_AllowedHeaders(t *testing.T) {
	cors := CORS([]string{"https://example.com"})
	handler := cors(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("Origin", "https://example.com")
	handler.ServeHTTP(w, r)

	headers := w.Header().Get("Access-Control-Allow-Headers")
	if headers == "" {
		t.Fatal("expected Access-Control-Allow-Headers header")
	}
	expected := "Authorization, Content-Type, X-Request-ID, X-Client-Version, X-Platform"
	if headers != expected {
		t.Fatalf("expected %q, got %q", expected, headers)
	}
}

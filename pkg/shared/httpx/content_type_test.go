package httpx

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequireContentType_AllowedJSON(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{}`))
	r.Header.Set("Content-Type", "application/json")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestRequireContentType_AllowedWithCharset(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{}`))
	r.Header.Set("Content-Type", "application/json; charset=utf-8")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 with charset param, got %d", w.Code)
	}
}

func TestRequireContentType_Rejected(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("hello"))
	r.Header.Set("Content-Type", "text/plain")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("expected 415, got %d", w.Code)
	}
}

func TestRequireContentType_MissingContentType(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{}`))
	// no Content-Type header
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("expected 415 for missing Content-Type, got %d", w.Code)
	}
}

func TestRequireContentType_MultipartAllowed(t *testing.T) {
	handler := RequireContentType("application/json", "multipart/form-data")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("--boundary\r\n\r\n"))
	r.Header.Set("Content-Type", "multipart/form-data; boundary=boundary")
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for multipart, got %d", w.Code)
	}
}

func TestRequireContentType_GetNoBodyPassThrough(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/games", nil)
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for GET without body, got %d", w.Code)
	}
}

func TestRequireContentType_DeleteNoBodyPassThrough(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodDelete, "/games/1", nil)
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for DELETE without body, got %d", w.Code)
	}
}

func TestRequireContentType_PostNoBodyPassThrough(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/sync", http.NoBody)
	r.ContentLength = 0
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for POST with empty body, got %d", w.Code)
	}
}

func TestRequireContentType_ErrorEnvelopeShape(t *testing.T) {
	handler := RequireContentType("application/json")(okHandler())

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("hello"))
	r.Header.Set("Content-Type", "text/plain")
	handler.ServeHTTP(w, r)

	ct := w.Header().Get("Content-Type")
	if !strings.Contains(ct, "application/json") {
		t.Fatalf("expected JSON response, got %q", ct)
	}
	body := w.Body.String()
	if !strings.Contains(body, "UNSUPPORTED_MEDIA_TYPE") {
		t.Fatalf("expected UNSUPPORTED_MEDIA_TYPE in body, got %s", body)
	}
}

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusOK)
	})
}

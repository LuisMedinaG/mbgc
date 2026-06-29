package httpx

import (
	"log/slog"
	"net/http"
	"runtime/debug"
	"strings"
	"time"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
	"github.com/google/uuid"
)

// Chain applies middlewares to h in order — first middleware is outermost.
//
//	httpx.Chain(router, httpx.Logger, httpx.RequestID, httpx.Recover)
//	// executes: Logger → RequestID → Recover → router
func Chain(h http.Handler, mw ...func(http.Handler) http.Handler) http.Handler {
	for i := len(mw) - 1; i >= 0; i-- {
		h = mw[i](h)
	}
	return h
}

// SecurityHeaders injects standard security-related HTTP headers into the response
// to mitigate common web vulnerabilities (e.g., XSS, Clickjacking, MIME-sniffing).
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		h.Set("Content-Security-Policy", "default-src 'none'")
		next.ServeHTTP(w, r)
	})
}

// ClientInfo reads X-Client-Version and X-Platform request headers and stores
// them in context. Missing headers are stored as empty strings — no request
// is rejected. Used for per-version logging and future server-side feature flags.
// ref: api-layer.CLIENT_INFO.1
func ClientInfo(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		version := strings.TrimSpace(r.Header.Get("X-Client-Version"))
		platform := strings.TrimSpace(r.Header.Get("X-Platform"))
		next.ServeHTTP(w, r.WithContext(withClientInfo(r.Context(), version, platform)))
	})
}

// CORS provides Cross-Origin Resource Sharing (CORS) support for the specified
// list of allowed origins. It handles both preflight OPTIONS requests and
// injecting the necessary headers into actual requests.
func CORS(allowedOrigins []string) func(http.Handler) http.Handler {
	allowed := make(map[string]struct{}, len(allowedOrigins))
	for _, o := range allowedOrigins {
		allowed[o] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" {
				// ref: api-layer.SEC.8 — Vary: Origin prevents caches from serving
				// one origin's ACAO response to another origin.
				w.Header().Add("Vary", "Origin")
			}
			if _, ok := allowed[origin]; ok {
				h := w.Header()
				h.Set("Access-Control-Allow-Origin", origin)
				h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID, X-Client-Version, X-Platform")
				h.Set("Access-Control-Allow-Credentials", "true")
				h.Set("Access-Control-Max-Age", "86400")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// Recover is a middleware that intercepts panics within handlers to prevent
// the server process from crashing. It logs the panic value and stack trace
// before returning a standard 500 Internal Server Error to the client.
// ref: monitoring.SINK.2
func Recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				Record(r, "panic", slog.LevelError,
					"value", v,
					"stack", string(debug.Stack()),
				)
				WriteJSON(w, http.StatusInternalServerError, NewError(apierr.CodeInternal, "internal server error"))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// RequestID ensures every request has a unique identifier. It reads the
// X-Request-ID header from the request (if present) or generates a new UUID.
// This ID is then injected into the request context and the response headers
// for end-to-end tracing.
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			id = uuid.NewString()
		}
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(withRequestID(r.Context(), id)))
	})
}

// Logger provides structured logging for every HTTP request. It records the
// method, path, status code, and latency.
//
// Event types:
//   - "request": Standard successful or client-error (4xx) requests.
//   - "server_error": Server-side errors (5xx).
//   - "auth_failure": Unauthorized attempts (401) specifically on /auth/* paths.
//
// ref: monitoring.SINK.1, monitoring.SINK.4, monitoring.COST.1
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rw, r)

		event := "request"
		level := slog.LevelInfo
		if rw.status >= 500 {
			event = "server_error"
			level = slog.LevelError
		} else if rw.status == http.StatusUnauthorized && strings.HasPrefix(r.URL.Path, "/auth/") {
			event = "auth_failure"
			level = slog.LevelWarn
		} else if rw.status >= 400 {
			level = slog.LevelInfo
		}

		attrs := []any{"status", rw.status, "latency_ms", time.Since(start).Milliseconds()}
		if v := ClientVersionFromContext(r.Context()); v != "" {
			attrs = append(attrs, "client_version", v)
		}
		if p := ClientPlatformFromContext(r.Context()); p != "" {
			attrs = append(attrs, "client_platform", p)
		}
		Record(r, event, level, attrs...)
	})
}

// statusWriter captures the HTTP status code written by a handler.
type statusWriter struct {
	http.ResponseWriter
	status int
}

func (sw *statusWriter) WriteHeader(status int) {
	sw.status = status
	sw.ResponseWriter.WriteHeader(status)
}

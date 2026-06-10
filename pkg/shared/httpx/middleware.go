package httpx

import (
	"log/slog"
	"net/http"
	"runtime/debug"
	"strings"
	"time"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
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

// SecurityHeaders adds standard security response headers.
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

// CORS applies CORS headers for the given list of allowed origins.
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
				h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID")
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

// Recover catches panics, logs the stack trace, and returns 500.
// ref: monitoring.SINK.2
func Recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				Record(r, "panic", slog.LevelError,
					"value", v,
					"stack", string(debug.Stack()),
				)
				WriteJSON(w, http.StatusInternalServerError, envelope.NewError(apierr.CodeInternal, "internal server error"))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// RequestID injects a unique request ID into context and the X-Request-ID response header.
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

// Logger logs method, path, status, and latency via Record (structured,
// allow-list-filtered). Event name is "request" for normal logs, with
// "server_error" for 5xx, "auth_failure" for 401 on /auth/*, and "request"
// for other 4xx (info level per monitoring.COST.1).
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

		Record(r, event, level,
			"status", rw.status,
			"latency_ms", time.Since(start).Milliseconds(),
		)
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

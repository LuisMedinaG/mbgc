package middleware

import (
	"log"
	"net/http"
	"time"
)

// responseWriter wraps http.ResponseWriter to capture the status code.
type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

// Logger is a middleware that logs each request's method, path, status, and
// duration.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rw, r)
		log.Printf("%s %s %d %s", r.Method, r.URL.Path, rw.status, time.Since(start))
	})
}

// OptionalAuth is like Auth but does not reject unauthenticated requests.
// If a valid Bearer token is present, the claims are injected into the context.
// If absent or invalid, the request proceeds without claims.
func OptionalAuth(secret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if len(header) > 7 && header[:7] == "Bearer " {
				tokenStr := header[7:]
				if claims, err := parseToken(tokenStr, secret); err == nil {
					r = r.WithContext(withClaims(r.Context(), claims))
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

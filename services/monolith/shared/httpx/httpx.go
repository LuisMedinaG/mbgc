// Package httpx provides HTTP middleware, JWT utilities, and context helpers
// shared across all services.
package httpx

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ── Middleware chain ──────────────────────────────────────────────────────────

// Middleware wraps an HTTP handler.
type Middleware func(http.Handler) http.Handler

// Chain applies middlewares left-to-right: Chain(h, A, B, C) → A(B(C(h))).
func Chain(h http.Handler, mw ...Middleware) http.Handler {
	for i := len(mw) - 1; i >= 0; i-- {
		h = mw[i](h)
	}
	return h
}

// ── Context helpers ───────────────────────────────────────────────────────────

type contextKey string

const (
	ctxUserID   contextKey = "userID"
	ctxUsername contextKey = "username"
	ctxIsAdmin  contextKey = "isAdmin"
)

// SetUser stores userID, username, and admin flag in the context.
func SetUser(ctx context.Context, id int64, username string, isAdmin bool) context.Context {
	ctx = context.WithValue(ctx, ctxUserID, id)
	ctx = context.WithValue(ctx, ctxUsername, username)
	ctx = context.WithValue(ctx, ctxIsAdmin, isAdmin)
	return ctx
}

// UserIDFromContext retrieves the authenticated user's ID.
func UserIDFromContext(ctx context.Context) (int64, bool) {
	v, ok := ctx.Value(ctxUserID).(int64)
	return v, ok
}

// UsernameFromContext retrieves the authenticated username.
func UsernameFromContext(ctx context.Context) string {
	v, _ := ctx.Value(ctxUsername).(string)
	return v
}

// IsAdminFromContext reports whether the authenticated user has admin privileges.
func IsAdminFromContext(ctx context.Context) bool {
	v, _ := ctx.Value(ctxIsAdmin).(bool)
	return v
}

// ── JWT ───────────────────────────────────────────────────────────────────────

// JWTClaims holds application-specific fields embedded in every access token.
type JWTClaims struct {
	UserID   int64  `json:"uid"`
	Username string `json:"username"`
	IsAdmin  bool   `json:"is_admin"`
	jwt.RegisteredClaims
}

// GenerateAccessToken mints a signed HS256 JWT that expires in 15 minutes.
func GenerateAccessToken(userID int64, username string, isAdmin bool, secret string) (string, error) {
	claims := JWTClaims{
		UserID:   userID,
		Username: username,
		IsAdmin:  isAdmin,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(15 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
}

// ParseAccessToken validates a signed JWT and returns its claims.
func ParseAccessToken(tokenStr, secret string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &JWTClaims{}, func(t *jwt.Token) (any, error) {
		if t.Method != jwt.SigningMethodHS256 {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(secret), nil
	})
	if err != nil || !token.Valid {
		return nil, err
	}
	return token.Claims.(*JWTClaims), nil
}

// ── Middleware implementations ────────────────────────────────────────────────

// RequireJWT validates an Authorization: Bearer <token> header and populates
// the request context with the user's identity. Returns 401 JSON on failure.
func RequireJWT(secret string) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			const prefix = "Bearer "
			auth := r.Header.Get("Authorization")
			if !strings.HasPrefix(auth, prefix) {
				WriteJSONError(w, http.StatusUnauthorized, "unauthorized")
				return
			}
			claims, err := ParseAccessToken(strings.TrimPrefix(auth, prefix), secret)
			if err != nil {
				WriteJSONError(w, http.StatusUnauthorized, "unauthorized")
				return
			}
			ctx := SetUser(r.Context(), claims.UserID, claims.Username, claims.IsAdmin)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// MethodGuard returns 405 when a route is reached with an unexpected HTTP method.
func MethodGuard(method string) Middleware {
	allow := strings.ToUpper(method)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != allow {
				w.Header().Set("Allow", allow)
				http.Error(w, fmt.Sprintf("method %s not allowed", r.Method), http.StatusMethodNotAllowed)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// SecurityHeaders adds browser hardening headers suitable for an API backend
// serving a React SPA from the same origin.
func SecurityHeaders() Middleware {
	csp := strings.Join([]string{
		"default-src 'self'",
		"script-src 'self'",
		"style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
		"font-src 'self' https://fonts.gstatic.com",
		"img-src 'self' data: https:",
		"object-src 'none'",
		"base-uri 'self'",
		"frame-ancestors 'none'",
	}, "; ")

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Security-Policy", csp)
			w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
			w.Header().Set("X-Content-Type-Options", "nosniff")
			w.Header().Set("X-Frame-Options", "DENY")
			w.Header().Set("Permissions-Policy", "camera=(), geolocation=(), microphone=()")
			if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
				w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
			}
			next.ServeHTTP(w, r)
		})
	}
}

// CORS adds permissive CORS headers for allowed origins.
// allowedOrigins is a comma-separated list of allowed origins (e.g. "http://localhost:5173,https://app.lumedina.dev").
// A single "*" allows all origins.
func CORS(allowedOrigins string) Middleware {
	set := make(map[string]struct{})
	for o := range strings.SplitSeq(allowedOrigins, ",") {
		if t := strings.TrimSpace(o); t != "" {
			set[t] = struct{}{}
		}
	}
	wildcard := allowedOrigins == "*"
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			_, allowed := set[origin]
			if wildcard || allowed {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ── Rate limiting ─────────────────────────────────────────────────────────────

// LoginLimiter tracks failed login attempts per IP in a sliding window.
type LoginLimiter struct {
	mu      sync.Mutex
	buckets map[string][]time.Time
	max     int
	window  time.Duration
}

// NewLoginLimiter creates a limiter allowing max attempts per window per IP.
func NewLoginLimiter(max int, window time.Duration) *LoginLimiter {
	return &LoginLimiter{buckets: make(map[string][]time.Time), max: max, window: window}
}

// Allow returns true if the IP has not exceeded its rate limit.
func (l *LoginLimiter) Allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now, cutoff := time.Now(), time.Now().Add(-l.window)
	attempts := prune(l.buckets[ip], cutoff)
	l.buckets[ip] = attempts
	_ = now
	return len(attempts) < l.max
}

// Record adds a failed attempt for the given IP.
func (l *LoginLimiter) Record(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.buckets[ip] = append(l.buckets[ip], time.Now())
}

// Cleanup removes stale entries older than the window.
func (l *LoginLimiter) Cleanup() {
	l.mu.Lock()
	defer l.mu.Unlock()
	cutoff := time.Now().Add(-l.window)
	for ip, ts := range l.buckets {
		if pruned := prune(ts, cutoff); len(pruned) == 0 {
			delete(l.buckets, ip)
		} else {
			l.buckets[ip] = pruned
		}
	}
}

func prune(ts []time.Time, cutoff time.Time) []time.Time {
	n := 0
	for _, t := range ts {
		if t.After(cutoff) {
			ts[n] = t
			n++
		}
	}
	return ts[:n]
}

// ClientIP extracts the real client IP, honouring X-Forwarded-For.
func ClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		for i := range xff {
			if xff[i] == ',' {
				return xff[:i]
			}
		}
		return xff
	}
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	return ip
}

// RateLimit wraps a handler and rejects requests that exceed the login limit.
func RateLimit(l *LoginLimiter) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !l.Allow(ClientIP(r)) {
				http.Error(w, "too many attempts, try again later", http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

// WriteJSONError writes {"error":"msg"} with the given status code.
func WriteJSONError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	fmt.Fprintf(w, `{"error":%q}`, msg)
}

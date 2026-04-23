package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/luismedinag/myboardgamecollection/auth"
)

type contextKey string

const claimsKey contextKey = "claims"

// withClaims stores claims in a context.
func withClaims(ctx context.Context, c *auth.Claims) context.Context {
	return context.WithValue(ctx, claimsKey, c)
}

// parseToken is an internal helper that delegates to auth.ParseToken.
func parseToken(tokenStr, secret string) (*auth.Claims, error) {
	return auth.ParseToken(tokenStr, secret)
}

// Auth returns middleware that validates a Bearer JWT and injects the claims
// into the request context. Unauthenticated requests receive 401.
func Auth(secret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if !strings.HasPrefix(header, "Bearer ") {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}
			tokenStr := strings.TrimPrefix(header, "Bearer ")
			claims, err := auth.ParseToken(tokenStr, secret)
			if err != nil {
				http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
				return
			}
			ctx := withClaims(r.Context(), claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// GetUser retrieves the authenticated user's claims from the request context.
// Returns nil if no claims are present.
func GetUser(r *http.Request) *auth.Claims {
	claims, _ := r.Context().Value(claimsKey).(*auth.Claims)
	return claims
}

// RequireAdmin wraps next and returns 403 when the authenticated user is not
// an admin. Auth middleware must run before RequireAdmin.
func RequireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims := GetUser(r)
		if claims == nil || claims.Role != "admin" {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

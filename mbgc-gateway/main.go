package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/luismedinag/mbgc-gateway/proxy"
	"github.com/luismedinag/mbgc-shared/middleware"
	"github.com/luismedinag/mbgc-shared/response"
)

// getEnv returns the value of the environment variable named by key, or
// fallback if the variable is not set or is empty.
func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// OptionalAuth attempts to parse a Bearer JWT from the Authorization header.
// If the token is valid, claims are stored in the request context exactly as
// middleware.Auth would. If the header is absent or the token is invalid the
// request continues without claims — no error is returned to the caller.
func OptionalAuth(secret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if strings.HasPrefix(header, "Bearer ") {
				tokenStr := strings.TrimPrefix(header, "Bearer ")
				claims := &middleware.Claims{}
				_, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (any, error) {
					if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
						return nil, jwt.ErrSignatureInvalid
					}
					return secret, nil
				})
				if err == nil {
					ctx := context.WithValue(r.Context(), middleware.ClaimsKey, claims)
					r = r.WithContext(ctx)
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// chain applies a slice of middleware in order (first middleware is outermost).
func chain(h http.Handler, mws ...func(http.Handler) http.Handler) http.Handler {
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}

func main() {
	port := getEnv("PORT", "8080")
	jwtSecret := []byte(getEnv("JWT_SECRET", ""))
	authURL := getEnv("AUTH_SERVICE_URL", "http://localhost:8081")
	gameURL := getEnv("GAME_SERVICE_URL", "http://localhost:8082")
	importerURL := getEnv("IMPORTER_SERVICE_URL", "http://localhost:8083")

	originsRaw := getEnv("ALLOWED_ORIGINS", "*")
	var origins []string
	for _, o := range strings.Split(originsRaw, ",") {
		o = strings.TrimSpace(o)
		if o != "" {
			origins = append(origins, o)
		}
	}

	// Build upstream proxy handlers.
	authProxy := proxy.New(authURL)
	gameProxy := proxy.New(gameURL)
	importerProxy := proxy.New(importerURL)

	requireAuth := middleware.Auth(jwtSecret)
	optionalAuth := OptionalAuth(jwtSecret)

	mux := http.NewServeMux()

	// /health — inline handler, no auth needed.
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		response.OK(w, "ok")
	})

	// /auth/* — no JWT required; the auth service handles its own authentication.
	mux.Handle("/auth/", authProxy)

	// /profile/* — JWT required.
	mux.Handle("/profile/", chain(authProxy, requireAuth))

	// /games/* — JWT optional (public reads; writes protected upstream).
	mux.Handle("/games/", chain(gameProxy, optionalAuth))

	// /collections/* — JWT required.
	mux.Handle("/collections/", chain(gameProxy, requireAuth))

	// /player-aids/* — JWT optional.
	mux.Handle("/player-aids/", chain(gameProxy, optionalAuth))

	// /import/* — JWT required.
	mux.Handle("/import/", chain(importerProxy, requireAuth))

	// Apply global middleware: CORS outermost, then Logging.
	handler := middleware.CORS(origins)(middleware.Logging(mux))

	addr := ":" + port
	slog.Info("mbgc-gateway starting", "addr", addr)
	if err := http.ListenAndServe(addr, handler); err != nil {
		slog.Error("server error", "err", err)
		os.Exit(1)
	}
}

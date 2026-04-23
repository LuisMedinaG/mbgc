package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"

	"github.com/luismedinag/mbgc-auth-service/db"
	"github.com/luismedinag/mbgc-auth-service/handlers"
	"github.com/luismedinag/mbgc-shared/middleware"
	"github.com/luismedinag/mbgc-shared/response"
)

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// requireUser rejects requests missing X-User-ID.
func requireUser(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-User-ID") == "" {
			response.Unauthorized(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// requireAdmin rejects requests where X-User-Role != "admin".
func requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-User-Role") != "admin" {
			response.Forbidden(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	port := getEnv("PORT", "8081")
	databaseURL := os.Getenv("DATABASE_URL")

	ctx := context.Background()
	pool, err := db.Connect(ctx, databaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	mux := http.NewServeMux()

	// Health check — no auth required.
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		response.OK(w, "ok")
	})

	// Authenticated user routes.
	mux.Handle("GET /profile", requireUser(handlers.GetProfile(pool)))
	mux.Handle("PUT /profile", requireUser(handlers.UpdateProfile(pool)))

	// Admin-only routes.
	mux.Handle("GET /profile/{user_id}", requireUser(requireAdmin(handlers.GetAnyProfile(pool))))
	mux.Handle("GET /profiles", requireUser(requireAdmin(handlers.ListProfiles(pool))))

	handler := middleware.Logging(mux)

	slog.Info("mbgc-auth-service starting", "port", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}
}

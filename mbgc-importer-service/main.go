package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"

	"github.com/luismedinag/mbgc-importer-service/db"
	"github.com/luismedinag/mbgc-importer-service/handlers"
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

func main() {
	port := getEnv("PORT", "8083")
	databaseURL := os.Getenv("DATABASE_URL")
	gameServiceURL := getEnv("GAME_SERVICE_URL", "http://localhost:8082")

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

	// Import routes — trust X-User-ID header injected by the gateway.
	mux.Handle("POST /import/bgg", requireUser(handlers.TriggerBGGImport(pool, gameServiceURL)))
	mux.Handle("POST /import/csv", requireUser(handlers.TriggerCSVImport(pool, gameServiceURL)))
	mux.Handle("GET /import/jobs/{id}", requireUser(handlers.GetImportJob(pool)))

	handler := middleware.Logging(mux)

	slog.Info("mbgc-importer-service starting", "port", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}
}

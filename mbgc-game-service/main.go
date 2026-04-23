package main

import (
	"log/slog"
	"net/http"
	"os"

	"github.com/luismedinag/mbgc-game-service/db"
	"github.com/luismedinag/mbgc-game-service/handlers"
	"github.com/luismedinag/mbgc-shared/middleware"
	"github.com/luismedinag/mbgc-shared/response"
)

func main() {
	port := getEnv("PORT", "8080")
	dbURL := mustEnv("DATABASE_URL")
	jwtSecret := []byte(mustEnv("JWT_SECRET"))

	conn, err := db.New(dbURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer conn.Close(nil)

	auth := middleware.Auth(jwtSecret)
	requireAdmin := middleware.RequireAdmin

	chain := func(h http.Handler, middlewares ...func(http.Handler) http.Handler) http.Handler {
		for i := len(middlewares) - 1; i >= 0; i-- {
			h = middlewares[i](h)
		}
		return h
	}

	mux := http.NewServeMux()

	// Health
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		response.OK(w, "ok")
	})

	// Games — public reads, admin writes
	mux.Handle("GET /games", handlers.ListGames(conn))
	mux.Handle("POST /games", chain(handlers.CreateGame(conn), auth, requireAdmin))
	mux.Handle("GET /games/{id}", handlers.GetGame(conn))
	mux.Handle("PUT /games/{id}", chain(handlers.UpdateGame(conn), auth, requireAdmin))
	mux.Handle("DELETE /games/{id}", chain(handlers.DeleteGame(conn), auth, requireAdmin))

	// Collections — authenticated user only
	mux.Handle("GET /collections", chain(handlers.ListCollection(conn), auth))
	mux.Handle("POST /collections", chain(handlers.AddToCollection(conn), auth))
	mux.Handle("PUT /collections/{id}", chain(handlers.UpdateCollectionEntry(conn), auth))
	mux.Handle("DELETE /collections/{id}", chain(handlers.RemoveFromCollection(conn), auth))

	// Player aids
	mux.Handle("GET /player-aids", handlers.ListPlayerAids(conn))
	mux.Handle("POST /player-aids", chain(handlers.UploadPlayerAid(conn), auth))
	mux.Handle("GET /player-aids/{id}/download", handlers.DownloadPlayerAid(conn))
	mux.Handle("DELETE /player-aids/{id}", chain(handlers.DeletePlayerAid(conn), auth))

	server := &http.Server{
		Addr:    ":" + port,
		Handler: middleware.Logging(mux),
	}

	slog.Info("mbgc-game-service starting", "port", port)
	if err := server.ListenAndServe(); err != nil {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		slog.Error("required environment variable not set", "key", key)
		os.Exit(1)
	}
	return v
}

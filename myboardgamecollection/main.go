package main

import (
	"log"
	"net/http"
	"os"

	appdb "github.com/luismedinag/myboardgamecollection/db"
	"github.com/luismedinag/myboardgamecollection/handlers"
	"github.com/luismedinag/myboardgamecollection/middleware"
)

func main() {
	port := envOr("PORT", "8080")
	dbPath := envOr("DB_PATH", "/data/mbgc.db")
	jwtSecret := envOr("JWT_SECRET", "changeme")

	db, err := appdb.New(dbPath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	mux := http.NewServeMux()

	// ---- HTMX / page routes ----
	mux.Handle("GET /", middleware.OptionalAuth(jwtSecret)(handlers.IndexPage(db)))
	mux.HandleFunc("GET /login", handlers.LoginPage)
	mux.HandleFunc("GET /register", handlers.RegisterPage)
	mux.Handle("GET /htmx/games", handlers.HTMXGames(db))
	mux.Handle("GET /htmx/collection",
		middleware.Auth(jwtSecret)(handlers.HTMXCollection(db)),
	)

	// ---- Auth API ----
	mux.Handle("POST /api/auth/register", handlers.Register(db))
	mux.Handle("POST /api/auth/login", handlers.Login(db))

	// ---- Games API (read: public; write: admin) ----
	mux.Handle("GET /api/games", handlers.ListGames(db))
	mux.Handle("GET /api/games/{id}", handlers.GetGame(db))
	mux.Handle("POST /api/games",
		middleware.Auth(jwtSecret)(
			middleware.RequireAdmin(handlers.CreateGame(db)),
		),
	)
	mux.Handle("PUT /api/games/{id}",
		middleware.Auth(jwtSecret)(
			middleware.RequireAdmin(handlers.UpdateGame(db)),
		),
	)
	mux.Handle("DELETE /api/games/{id}",
		middleware.Auth(jwtSecret)(
			middleware.RequireAdmin(handlers.DeleteGame(db)),
		),
	)

	// ---- Collections API (auth required) ----
	mux.Handle("GET /api/collections",
		middleware.Auth(jwtSecret)(handlers.ListCollection(db)),
	)
	mux.Handle("POST /api/collections",
		middleware.Auth(jwtSecret)(handlers.AddToCollection(db)),
	)
	mux.Handle("PUT /api/collections/{id}",
		middleware.Auth(jwtSecret)(handlers.UpdateCollectionEntry(db)),
	)
	mux.Handle("DELETE /api/collections/{id}",
		middleware.Auth(jwtSecret)(handlers.RemoveFromCollection(db)),
	)

	// ---- Import API (auth required) ----
	mux.Handle("POST /api/import/bgg",
		middleware.Auth(jwtSecret)(handlers.ImportBGG(db)),
	)
	mux.Handle("POST /api/import/csv",
		middleware.Auth(jwtSecret)(handlers.ImportCSV(db)),
	)

	// ---- Health ----
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`)) //nolint:errcheck
	})

	handler := middleware.Logger(mux)

	log.Printf("listening on :%s", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatalf("server: %v", err)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/bgg"
	"github.com/LuisMedinaG/mbgc/services/monolith/services/auth"
	"github.com/LuisMedinaG/mbgc/services/monolith/services/collections"
	"github.com/LuisMedinaG/mbgc/services/monolith/services/files"
	"github.com/LuisMedinaG/mbgc/services/monolith/services/games"
	"github.com/LuisMedinaG/mbgc/services/monolith/services/importer"
	"github.com/LuisMedinaG/mbgc/services/monolith/services/profile"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/db"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"

	"github.com/joho/godotenv"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	if _, err := os.Stat(".env"); err == nil {
		if err := godotenv.Load(); err != nil {
			slog.Error("load .env failed", "error", err)
			os.Exit(1)
		}
	}

	port := "8080"
	if p := os.Getenv("PORT"); p != "" {
		port = p
	}
	dbPath := "games.db"
	if p := os.Getenv("DB_PATH"); p != "" {
		dbPath = p
	}
	dataDir := "data"
	if p := os.Getenv("DATA_DIR"); p != "" {
		dataDir = p
	}
	jwtSecret := os.Getenv("SESSION_SECRET")
	if jwtSecret == "" {
		slog.Warn("SESSION_SECRET is not set; using an insecure default — set it in production")
		jwtSecret = "dev-secret-change-me-in-production"
	}
	reactOrigin := os.Getenv("REACT_ORIGIN")
	if reactOrigin == "" {
		reactOrigin = "http://localhost:5173"
	}

	// ── Database ─────────────────────────────────────────────────────────────
	sqlDB, err := db.Open(dbPath)
	if err != nil {
		slog.Error("database init failed", "error", err)
		os.Exit(1)
	}
	defer sqlDB.Close()

	// ── Services ──────────────────────────────────────────────────────────────
	authStore := auth.NewStore(sqlDB)
	gameStore := games.NewStore(sqlDB)
	collStore := collections.NewStore(sqlDB)

	if err := gameStore.PopulateTaxonomy(); err != nil {
		slog.Warn("taxonomy migration failed", "error", err)
	}
	if err := authStore.DeleteExpiredSessions(); err != nil {
		slog.Warn("failed to purge expired sessions", "error", err)
	}

	// BGG client (optional).
	var bggClient *bgg.Client
	if token := os.Getenv("BGG_TOKEN"); token != "" {
		bggClient = bgg.New(token)
		slog.Info("BGG auth: using token")
	} else if cookie := os.Getenv("BGG_COOKIE"); cookie != "" {
		bggClient = bgg.NewWithCookies(cookie)
		slog.Info("BGG auth: using cookie")
	}

	// Ensure data directories exist.
	_ = os.MkdirAll(filepath.Join(dataDir, "uploads"), 0o755)
	_ = os.MkdirAll(filepath.Join(dataDir, "images"), 0o755)

	// Login rate limiter: 10 attempts per 15 minutes per IP.
	loginLimiter := httpx.NewLoginLimiter(10, 15*time.Minute)

	// ── Handlers ─────────────────────────────────────────────────────────────
	authH := auth.NewHandler(authStore, jwtSecret, loginLimiter)
	gamesH := games.NewHandler(gameStore)
	collH := collections.NewHandler(collStore, gameStore)
	importH := importer.NewHandler(authStore, gameStore, bggClient)
	filesH := files.NewHandler(gameStore, dataDir)
	profileH := profile.NewHandler(authStore)

	// ── Router ────────────────────────────────────────────────────────────────
	mux := http.NewServeMux()

	// Middleware factories.
	pub := func(method string, hf http.HandlerFunc) http.Handler {
		return httpx.Chain(hf, httpx.MethodGuard(method))
	}
	protected := func(method string, hf http.HandlerFunc) http.Handler {
		return httpx.Chain(hf, httpx.MethodGuard(method), httpx.RequireJWT(jwtSecret))
	}

	// Auth — public.
	mux.Handle("POST /api/v1/auth/login", pub(http.MethodPost, authH.Login))
	mux.Handle("POST /api/v1/auth/refresh", pub(http.MethodPost, authH.Refresh))
	mux.Handle("POST /api/v1/auth/logout", pub(http.MethodPost, authH.Logout))

	// Auth — protected.
	mux.Handle("GET /api/v1/ping", protected(http.MethodGet, authH.Ping))

	// Games.
	mux.Handle("GET /api/v1/games", protected(http.MethodGet, gamesH.ListGames))
	mux.Handle("GET /api/v1/games/{id}", protected(http.MethodGet, gamesH.GetGame))
	mux.Handle("DELETE /api/v1/games/{id}", protected(http.MethodDelete, gamesH.DeleteGame))
	mux.Handle("POST /api/v1/games/{id}/collections", protected(http.MethodPost, gamesH.SetGameCollections))
	mux.Handle("POST /api/v1/games/bulk-collections", protected(http.MethodPost, gamesH.BulkCollections))

	// Collections.
	mux.Handle("GET /api/v1/collections", protected(http.MethodGet, collH.ListCollections))
	mux.Handle("POST /api/v1/collections", protected(http.MethodPost, collH.CreateCollection))
	mux.Handle("PUT /api/v1/collections/{id}", protected(http.MethodPut, collH.UpdateCollection))
	mux.Handle("DELETE /api/v1/collections/{id}", protected(http.MethodDelete, collH.DeleteCollection))

	// Discover.
	mux.Handle("GET /api/v1/discover", protected(http.MethodGet, collH.Discover))

	// Import.
	mux.Handle("POST /api/v1/import/sync", protected(http.MethodPost, importH.Sync))
	mux.Handle("POST /api/v1/import/csv/preview", protected(http.MethodPost, importH.CSVPreview))
	mux.Handle("POST /api/v1/import/csv", protected(http.MethodPost, importH.CSVImport))

	// Profile.
	mux.Handle("GET /api/v1/profile", protected(http.MethodGet, profileH.GetProfile))
	mux.Handle("PUT /api/v1/profile/bgg-username", protected(http.MethodPut, profileH.SetBGGUsername))
	mux.Handle("PUT /api/v1/profile/password", protected(http.MethodPut, profileH.ChangePassword))

	// Files (rules URL, player aids).
	mux.Handle("PUT /api/v1/games/{id}/rules-url", protected(http.MethodPut, filesH.UpdateRulesURL))
	mux.Handle("POST /api/v1/games/{id}/player-aids", protected(http.MethodPost, filesH.UploadPlayerAid))
	mux.Handle("DELETE /api/v1/games/{id}/player-aids/{aid_id}", protected(http.MethodDelete, filesH.DeletePlayerAid))

	// Uploaded files (player aid images served from disk).
	uploads := http.StripPrefix("/uploads/", http.FileServer(http.Dir(filepath.Join(dataDir, "uploads"))))
	mux.Handle("GET /uploads/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		uploads.ServeHTTP(w, r)
	}))

	// ── HTTP server ───────────────────────────────────────────────────────────
	server := &http.Server{
		Addr: ":" + port,
		Handler: httpx.Chain(mux,
			httpx.SecurityHeaders(),
			httpx.CORS(reactOrigin),
		),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	slog.Info("listening", "addr", "http://localhost:"+port)
	go func() {
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	// Periodic maintenance.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := authStore.DeleteExpiredSessions(); err != nil {
					slog.Warn("session cleanup failed", "error", err)
				}
				loginLimiter.Cleanup()
			case <-ctx.Done():
				return
			}
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
	}
	slog.Info("stopped")
}

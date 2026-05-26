package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
	"github.com/LuisMedinaG/mbgc/services/api/internal/auth"
	"github.com/LuisMedinaG/mbgc/services/api/internal/config"
	"github.com/LuisMedinaG/mbgc/services/api/internal/game"
	"github.com/LuisMedinaG/mbgc/services/api/internal/importer"
	apijwt "github.com/LuisMedinaG/mbgc/services/api/internal/jwt"
	"github.com/LuisMedinaG/mbgc/services/api/internal/profile"
	"github.com/LuisMedinaG/mbgc/services/api/internal/seed"
)

func main() {
	cfg := config.Load()

	pool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	verifier, err := apijwt.NewVerifier(context.Background(), cfg.SupabaseURL, cfg.JWTSecret)
	if err != nil {
		slog.Error("failed to init JWT verifier", "error", err)
		os.Exit(1)
	}
	authMiddleware := verifier.RequireAuth

	if cfg.SeedAdminEmail != "" {
		if err := seed.AdminUser(context.Background(), cfg, pool); err != nil {
			slog.Warn("admin seed skipped", "reason", err)
		}
	}

	authStore := auth.NewStore(pool)
	authHandler := auth.NewHandler(authStore)

	profileStore := profile.NewStore(pool)
	profileSvc := profile.NewService(profileStore)
	profileHandler := profile.NewHandler(profileSvc)

	gameStore := game.NewStore(pool)
	gameSvc := game.NewService(gameStore)
	gameHandler := game.NewHandler(gameSvc)

	bggClient := importer.NewClient(cfg.BGGToken, cfg.BGGCookie)
	importStore := importer.NewStore(pool)
	importSvc := importer.NewService(importStore, bggClient, gameSvc)
	importHandler := importer.NewHandler(importSvc, cfg.SyncLimitUser, cfg.SyncLimitAdmin)

	mux := http.NewServeMux()
	authHandler.RegisterRoutes(mux, authMiddleware)
	profileHandler.RegisterRoutes(mux, authMiddleware)
	gameHandler.RegisterRoutes(mux, authMiddleware)
	importHandler.RegisterRoutes(mux, authMiddleware)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	origins := []string{}
	if cfg.AllowedOrigin != "" {
		origins = append(origins, cfg.AllowedOrigin)
	}

	srv := &http.Server{
		Addr: ":" + cfg.Port,
		Handler: httpx.Chain(mux,
			// ref: auth.MIDDLEWARE.1 — Logger logs method, path, status, latency via slog
			httpx.Logger,
			// ref: auth.MIDDLEWARE.2 — RequestID attaches unique UUID
			httpx.RequestID,
			// ref: auth.MIDDLEWARE.3 — Recover catches panics, returns 500
			httpx.Recover,
			// ref: auth.MIDDLEWARE.4 — SecurityHeaders sets nosniff, DENY, CSP
			httpx.SecurityHeaders,
			// ref: auth.MIDDLEWARE.5 — CORS validates origin
			httpx.CORS(origins),
		),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("api starting", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("shutdown error", "error", err)
	}
	slog.Info("api stopped")
}

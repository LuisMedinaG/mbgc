package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/LuisMedinaG/mbgc/services/api/internal/httpx"
	"github.com/LuisMedinaG/mbgc/services/api/internal/auth"
	"github.com/LuisMedinaG/mbgc/services/api/internal/catalog"
	"github.com/LuisMedinaG/mbgc/services/api/internal/config"
	"github.com/LuisMedinaG/mbgc/services/api/internal/importer"
	apijwt "github.com/LuisMedinaG/mbgc/services/api/internal/jwt"
	"github.com/LuisMedinaG/mbgc/services/api/internal/profile"
	"github.com/LuisMedinaG/mbgc/services/api/internal/seed"
	migrations "github.com/LuisMedinaG/mbgc/services/api/migrations"
)

func heartbeat(ctx context.Context, interval time.Duration) {
	httpx.Record(nil, "heartbeat", slog.LevelInfo)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			httpx.Record(nil, "heartbeat", slog.LevelInfo)
		}
	}
}

func runMigrations(databaseURL string) error {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return fmt.Errorf("open db for migrations: %w", err)
	}
	defer db.Close()

	src, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return fmt.Errorf("migration source: %w", err)
	}
	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		return fmt.Errorf("migration driver: %w", err)
	}
	m, err := migrate.NewWithInstance("iofs", src, "postgres", driver)
	if err != nil {
		return fmt.Errorf("migrate init: %w", err)
	}
	defer m.Close()
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		var dirtyErr migrate.ErrDirty
		if errors.As(err, &dirtyErr) {
			// Previous startup crashed mid-migration; all SQL uses IF NOT EXISTS / OR REPLACE
			// so re-running from the dirty version is safe.
			slog.Warn("dirty migration state detected, resetting and retrying", "version", dirtyErr.Version)
			if ferr := m.Force(dirtyErr.Version - 1); ferr != nil {
				return fmt.Errorf("reset dirty migration v%d: %w", dirtyErr.Version, ferr)
			}
			if rerr := m.Up(); rerr != nil && rerr != migrate.ErrNoChange {
				return fmt.Errorf("migrate up after dirty reset: %w", rerr)
			}
			return nil
		}
		return fmt.Errorf("migrate up: %w", err)
	}
	return nil
}

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))

	if os.Getenv("MONITORING_DISABLED") == "true" {
		httpx.Disabled = true
		slog.Info("monitoring disabled via MONITORING_DISABLED env var")
	}

	cfg, err := config.Load()
	if err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}

	// ref: monitoring.OBSERVABILITY.2 — heartbeat goroutine. Cancelled on
	// shutdown so it stops cleanly with the rest of the service.
	hbCtx, hbCancel := context.WithCancel(context.Background())
	defer hbCancel()
	go heartbeat(hbCtx, 5*time.Minute)

	if os.Getenv("SKIP_MIGRATIONS") != "true" {
		if err := runMigrations(cfg.DatabaseURL); err != nil {
			slog.Error("migrations failed", "error", err)
			os.Exit(1)
		}
	}

	// ref: api-layer.INFRA.1 — explicit pool config: 10 conns/instance, 2 warm,
	// 30min lifetime (Supabase preference), 5min idle, 1min health check.
	poolCfg, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to parse database URL", "error", err)
		os.Exit(1)
	}
	poolCfg.MaxConns = 10
	poolCfg.MinConns = 2
	poolCfg.MaxConnLifetime = 30 * time.Minute
	poolCfg.MaxConnIdleTime = 5 * time.Minute
	poolCfg.HealthCheckPeriod = 1 * time.Minute
	pool, err := pgxpool.NewWithConfig(context.Background(), poolCfg)
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
	authHandler := auth.NewHandler(authStore, cfg.SupabaseURL, cfg.ServiceRoleKey, httpx.DefaultClient)

	profileStore := profile.NewStore(pool)
	profileSvc := profile.NewService(profileStore)
	profileHandler := profile.NewHandler(profileSvc)

	catalogStore := catalog.NewStore(pool)
	catalogHandler := catalog.NewHandler(catalogStore)

	bggClient := importer.NewClient(cfg.BGGToken, cfg.BGGCookie)
	importStore := importer.NewStore(pool)
	importSvc := importer.NewService(importStore, bggClient, catalogStore, profileSvc)
	importHandler := importer.NewHandler(importSvc, cfg.SyncLimitUser, cfg.SyncLimitAdmin)

	// ref: api-layer.SEC.5 — 5 req/s burst 10 on login/refresh/logout prevents brute-force
	rateLimit := httpx.RateLimiter(5, 10)
	// Global rate limiter: 30 req/s per IP, burst 60 — protects all routes from basic flood attacks.
	globalRateLimit := httpx.RateLimiter(30, 60)

	mux := http.NewServeMux()
	authHandler.RegisterRoutes(mux, authMiddleware, rateLimit)
	profileHandler.RegisterRoutes(mux, authMiddleware)
	catalogHandler.RegisterRoutes(mux, authMiddleware)
	importHandler.RegisterRoutes(mux, authMiddleware)
	// ref: api-layer.HEALTH.1 — liveness probe, no deps, always 200 if process is up
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	// ref: api-layer.HEALTH.2 — readiness probe: DB ping + JWKS reachability, 503 on failure
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := pool.Ping(ctx); err != nil {
			slog.Warn("readyz: db ping failed", "error", err)
			httpx.WriteJSON(w, http.StatusServiceUnavailable,
				httpx.NewError("service_unavailable", "database unavailable"))
			return
		}
		if err := verifier.Ping(ctx); err != nil {
			slog.Warn("readyz: jwks ping failed", "error", err)
			httpx.WriteJSON(w, http.StatusServiceUnavailable,
				httpx.NewError("service_unavailable", "auth service unavailable"))
			return
		}
		httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	srv := &http.Server{
		Addr: ":" + cfg.Port,
		Handler: httpx.Chain(mux,
			// ref: auth.MIDDLEWARE.1 — Logger logs method, path, status, latency via slog
			httpx.Logger,
			// ref: api-layer.CLIENT_INFO.1 — extracts X-Client-Version/X-Platform into context
			httpx.ClientInfo,
			// ref: auth.MIDDLEWARE.2 — RequestID attaches unique UUID
			httpx.RequestID,
			// ref: auth.MIDDLEWARE.3 — Recover catches panics, returns 500
			httpx.Recover,
			globalRateLimit,
			// ref: api-layer.SEC.6 — caps JSON request bodies at 1MB
			httpx.LimitBodySize(1<<20),
			// ref: auth.MIDDLEWARE.4 — SecurityHeaders sets nosniff, DENY, CSP
			httpx.SecurityHeaders,
			// ref: auth.MIDDLEWARE.5 — CORS validates origin; comma-separated ALLOWED_ORIGINS env var
			httpx.CORS(cfg.AllowedOrigins),
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

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

	"github.com/LuisMedinaG/mbgc/services/importer/internal/bgg"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/config"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/handler"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/service"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/store"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

func main() {
	cfg := config.Load()

	pool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	bggClient := bgg.NewClient(cfg.BGGToken, cfg.BGGCookie)
	st := store.New(pool)
	svc := service.New(st, bggClient, nil) // game client not implemented yet
	h := handler.New(svc, cfg)

	mux := http.NewServeMux()
	h.RegisterRoutes(mux)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	srv := &http.Server{
		Addr: ":" + cfg.Port,
		Handler: httpx.Chain(mux,
			httpx.Logger,
			httpx.RequestID,
			httpx.Recover,
			httpx.TrustGatewayHeaders,
		),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("importer-service starting", "port", cfg.Port)
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
	slog.Info("importer-service stopped")
}

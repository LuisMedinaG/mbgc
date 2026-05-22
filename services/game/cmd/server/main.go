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

	"github.com/LuisMedinaG/mbgc/services/game/internal/config"
	"github.com/LuisMedinaG/mbgc/services/game/internal/handler"
	"github.com/LuisMedinaG/mbgc/services/game/internal/service"
	"github.com/LuisMedinaG/mbgc/services/game/internal/store"
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

	st := store.New(pool, cfg.DataDir)
	svc := service.New(st)
	h := handler.New(svc)

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
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 60 * time.Second, // longer for file uploads
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("game-service starting", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("shutdown error", "error", err)
	}
	slog.Info("game-service stopped")
}

package config

import (
	"log/slog"
	"os"
)

// Config holds all runtime configuration loaded from environment variables.
type Config struct {
	Port               string
	JWTSecret          string
	SupabaseURL        string
	AuthServiceURL     string
	GameServiceURL     string
	ImporterServiceURL string
	AllowedOrigin      string
}

func Load() Config {
	return Config{
		Port:               getenv("PORT", "8000"),
		JWTSecret:          mustenv("SUPABASE_JWT_SECRET"),
		SupabaseURL:        getenv("SUPABASE_URL", "https://mlltpfszhtxhphoaeydh.supabase.co"),
		AuthServiceURL:     getenv("AUTH_SERVICE_URL", "http://localhost:8001"),
		GameServiceURL:     getenv("GAME_SERVICE_URL", "http://localhost:8002"),
		ImporterServiceURL: getenv("IMPORTER_SERVICE_URL", "http://localhost:8003"),
		AllowedOrigin:      getenv("ALLOWED_ORIGIN", "http://localhost:5173"),
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func mustenv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		slog.Error("required env var not set", "key", key)
		os.Exit(1)
	}
	return v
}

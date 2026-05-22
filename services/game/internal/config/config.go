package config

import (
	"log/slog"
	"os"
)

type Config struct {
	Port        string
	DatabaseURL string
	DataDir     string // directory for player aid file uploads
}

func Load() Config {
	return Config{
		Port:        getenv("PORT", "8002"),
		DatabaseURL: mustenv("DATABASE_URL"),
		DataDir:     getenv("DATA_DIR", "data"),
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

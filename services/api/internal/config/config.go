package config

import (
	"log/slog"
	"os"
	"strconv"
)

type Config struct {
	Port           string
	DatabaseURL    string
	SupabaseURL    string
	JWTSecret      string
	ServiceRoleKey string
	AllowedOrigin  string
	BGGToken       string
	BGGCookie      string
	SyncLimitUser  int
	SyncLimitAdmin int
	// Admin seed — only used on first boot if set. Idempotent.
	SeedAdminEmail    string
	SeedAdminPassword string
}

func Load() Config {
	return Config{
		Port:        getenv("PORT", "8080"),
		DatabaseURL: mustenv("DATABASE_URL"),
		SupabaseURL: mustenv("SUPABASE_URL"),
		// Optional legacy HS256 shared secret — leave empty for JWKS-only (recommended).
		JWTSecret:         os.Getenv("SUPABASE_JWT_SECRET"),
		ServiceRoleKey:    mustenv("SUPABASE_SERVICE_ROLE_KEY"),
		AllowedOrigin:     getenv("ALLOWED_ORIGIN", "http://localhost:5173"),
		BGGToken:          os.Getenv("BGG_TOKEN"),
		BGGCookie:         os.Getenv("BGG_COOKIE"),
		SyncLimitUser:     getenvInt("SYNC_LIMIT_USER", 3),
		SyncLimitAdmin:    getenvInt("SYNC_LIMIT_ADMIN", 20),
		SeedAdminEmail:    os.Getenv("SEED_ADMIN_EMAIL"),
		SeedAdminPassword: os.Getenv("SEED_ADMIN_PASSWORD"),
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

func getenvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

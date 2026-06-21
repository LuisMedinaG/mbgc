package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
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
	SeedAdminUsername string // optional display name; falls back to email in JWTs if unset
}

// Load reads configuration from environment variables. Returns an error if any
// required variable is missing so callers can handle it without os.Exit.
func Load() (Config, error) {
	dbURL, err := requireenv("DATABASE_URL") // ref: api-layer.CONFIG.1
	if err != nil {
		return Config{}, err
	}
	supabaseURL, err := requireenv("SUPABASE_URL") // ref: api-layer.CONFIG.2
	if err != nil {
		return Config{}, err
	}
	serviceRoleKey, err := requireenv("SUPABASE_SERVICE_ROLE_KEY")
	if err != nil {
		return Config{}, err
	}
	return Config{
		Port:        getenv("PORT", "8080"),              // ref: api-layer.CONFIG.3 — defaults to 8080
		DatabaseURL: sanitizeDatabaseURL(dbURL),
		SupabaseURL: supabaseURL,
		// Optional legacy HS256 shared secret — leave empty for JWKS-only (recommended).
		JWTSecret:         os.Getenv("SUPABASE_JWT_SECRET"),
		ServiceRoleKey:    serviceRoleKey,
		AllowedOrigin:     getenv("ALLOWED_ORIGIN", "http://localhost:5173"), // ref: api-layer.CONFIG.4 — defaults to localhost:5173
		BGGToken:          os.Getenv("BGG_TOKEN"),                            // ref: api-layer.CONFIG.5 — optional; importer disabled if absent
		BGGCookie:         os.Getenv("BGG_COOKIE"),                           // ref: api-layer.CONFIG.5
		SyncLimitUser:     getenvInt("SYNC_LIMIT_USER", 3),                   // ref: api-layer.CONFIG.6 — defaults to 3
		SyncLimitAdmin:    getenvInt("SYNC_LIMIT_ADMIN", 20),                 // ref: api-layer.CONFIG.6 — defaults to 20
		SeedAdminEmail:    os.Getenv("SEED_ADMIN_EMAIL"),
		SeedAdminPassword: os.Getenv("SEED_ADMIN_PASSWORD"),
		SeedAdminUsername: os.Getenv("SEED_ADMIN_USERNAME"),
	}, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func requireenv(key string) (string, error) {
	v := os.Getenv(key)
	if v == "" {
		return "", fmt.Errorf("required environment variable %q is not set", key)
	}
	return v, nil
}

// sanitizeDatabaseURL re-encodes the password in a postgres URL so that
// special characters (common in Supabase-generated passwords) don't fail
// Go's strict net/url parser used by pgx.
func sanitizeDatabaseURL(rawURL string) string {
	schemeEnd := strings.Index(rawURL, "://")
	if schemeEnd < 0 {
		return rawURL // DSN key=value format — no encoding needed
	}
	rest := rawURL[schemeEnd+3:]
	atIdx := strings.LastIndex(rest, "@")
	if atIdx < 0 {
		return rawURL
	}
	userinfo := rest[:atIdx]
	hostpath := rest[atIdx+1:]
	colonIdx := strings.Index(userinfo, ":")
	if colonIdx < 0 {
		return rawURL
	}
	username := userinfo[:colonIdx]
	password := userinfo[colonIdx+1:]

	host, path := hostpath, ""
	if i := strings.Index(hostpath, "/"); i >= 0 {
		host, path = hostpath[:i], hostpath[i:]
	}
	rawQuery := ""
	if i := strings.Index(path, "?"); i >= 0 {
		path, rawQuery = path[:i], path[i+1:]
	}
	u := &url.URL{
		Scheme:   rawURL[:schemeEnd],
		User:     url.UserPassword(username, password),
		Host:     host,
		Path:     path,
		RawQuery: rawQuery,
	}
	return u.String()
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

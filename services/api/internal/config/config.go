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
	AllowedOrigins []string
	BGGToken       string
	BGGCookie      string
	SyncLimitBasic int // basic tier: syncs per week
	SyncLimitPro   int // pro tier: syncs per day (≈hourly)
	SyncLimitAdmin int // admin hard cap: syncs per day
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
		Port:        getenv("PORT", "8080"), // ref: api-layer.CONFIG.3 — defaults to 8080
		DatabaseURL: sanitizeDatabaseURL(dbURL),
		SupabaseURL: supabaseURL,
		// Optional legacy HS256 shared secret — leave empty for JWKS-only (recommended).
		JWTSecret:         os.Getenv("SUPABASE_JWT_SECRET"),
		ServiceRoleKey:    serviceRoleKey,
		AllowedOrigins:    getenvList("ALLOWED_ORIGINS", "http://localhost:5173"), // ref: api-layer.CONFIG.4 — comma-separated; defaults to localhost:5173
		BGGToken:          os.Getenv("BGG_TOKEN"),                                 // ref: api-layer.CONFIG.5 — optional; importer disabled if absent
		BGGCookie:         os.Getenv("BGG_COOKIE"),                                // ref: api-layer.CONFIG.5
		SyncLimitBasic:    getenvInt("SYNC_LIMIT_BASIC", 1),                       // 1 per week for basic users
		SyncLimitPro:      getenvInt("SYNC_LIMIT_PRO", 24),                        // ≈1/hour for pro users
		SyncLimitAdmin:    getenvInt("SYNC_LIMIT_ADMIN", 100),                     // hard safety cap for admins
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

func getenvList(key, fallback string) []string {
	v := os.Getenv(key)
	if v == "" {
		v = fallback
	}
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
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

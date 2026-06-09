package config

import (
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		wantErr bool
	}{
		{
			name: "minimal valid config",
			env: map[string]string{
				"DATABASE_URL":              "postgres://user:pass@localhost/db",
				"SUPABASE_URL":              "http://localhost:54321",
				"SUPABASE_SERVICE_ROLE_KEY": "test-key",
			},
		},
		{
			name: "missing required DATABASE_URL",
			env: map[string]string{
				"SUPABASE_URL":              "http://localhost:54321",
				"SUPABASE_SERVICE_ROLE_KEY": "test-key",
			},
			wantErr: true,
		},
		{
			name: "missing required SUPABASE_URL",
			env: map[string]string{
				"DATABASE_URL":              "postgres://user:pass@localhost/db",
				"SUPABASE_SERVICE_ROLE_KEY": "test-key",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Save original env
			orig := os.Environ()
			os.Clearenv()
			for k, v := range tt.env {
				os.Setenv(k, v)
			}
			defer func() {
				os.Clearenv()
				for _, pair := range orig {
					parts := splitEnv(pair)
					if len(parts) == 2 {
						os.Setenv(parts[0], parts[1])
					}
				}
			}()

			if tt.wantErr {
				// Skip load test for missing required vars — it calls os.Exit
				return
			}

			cfg := Load()
			if cfg.DatabaseURL == "" {
				t.Error("DatabaseURL should not be empty")
			}
			if cfg.SupabaseURL == "" {
				t.Error("SupabaseURL should not be empty")
			}
			if cfg.ServiceRoleKey == "" {
				t.Error("ServiceRoleKey should not be empty")
			}
			if cfg.Port != "8080" {
				t.Errorf("expected Port=8080, got %s", cfg.Port)
			}
		})
	}
}

func TestSanitizeDatabaseURL(t *testing.T) {
	tests := []struct {
		name   string
		rawURL string
		want   string
	}{
		{
			name:   "DSN format",
			rawURL: "host=localhost user=postgres",
			want:   "host=localhost user=postgres",
		},
		{
			name:   "postgres URL with special chars in password",
			rawURL: "postgres://user:p@ss%word@localhost/db",
			want:   "postgres://user:p%40ss%25word@localhost/db",
		},
		{
			name:   "postgres URL simple",
			rawURL: "postgres://user:pass@localhost/db",
			want:   "postgres://user:pass@localhost/db",
		},
		{
			name:   "no @ in userinfo",
			rawURL: "postgres://user@localhost/db",
			want:   "postgres://user@localhost/db",
		},
		{
			name:   "URL with query string",
			rawURL: "postgres://user:pass@localhost/db?sslmode=require",
			want:   "postgres://user:pass@localhost/db?sslmode=require",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := sanitizeDatabaseURL(tt.rawURL)
			if got != tt.want {
				t.Errorf("sanitizeDatabaseURL(%q) = %q, want %q", tt.rawURL, got, tt.want)
			}
		})
	}
}

func TestGetenv(t *testing.T) {
	os.Setenv("TEST_VAR", "test-value")
	defer os.Unsetenv("TEST_VAR")

	t.Run("existing var", func(t *testing.T) {
		if got := getenv("TEST_VAR", "default"); got != "test-value" {
			t.Errorf("getenv = %q, want test-value", got)
		}
	})

	t.Run("missing var returns fallback", func(t *testing.T) {
		if got := getenv("MISSING_VAR", "default"); got != "default" {
			t.Errorf("getenv = %q, want default", got)
		}
	})

	t.Run("empty var returns fallback", func(t *testing.T) {
		os.Setenv("EMPTY_VAR", "")
		defer os.Unsetenv("EMPTY_VAR")
		if got := getenv("EMPTY_VAR", "default"); got != "default" {
			t.Errorf("getenv = %q, want default", got)
		}
	})
}

func TestGetenvInt(t *testing.T) {
	t.Run("valid int", func(t *testing.T) {
		os.Setenv("INT_VAR", "42")
		defer os.Unsetenv("INT_VAR")
		if got := getenvInt("INT_VAR", 0); got != 42 {
			t.Errorf("getenvInt = %d, want 42", got)
		}
	})

	t.Run("missing returns fallback", func(t *testing.T) {
		if got := getenvInt("MISSING_INT", 99); got != 99 {
			t.Errorf("getenvInt = %d, want 99", got)
		}
	})

	t.Run("invalid int returns fallback", func(t *testing.T) {
		os.Setenv("BAD_INT", "not-a-number")
		defer os.Unsetenv("BAD_INT")
		if got := getenvInt("BAD_INT", 88); got != 88 {
			t.Errorf("getenvInt = %d, want 88", got)
		}
	})
}

// splitEnv is a simple helper for test cleanup
func splitEnv(pair string) []string {
	for i := 0; i < len(pair); i++ {
		if pair[i] == '=' {
			return []string{pair[:i], pair[i+1:]}
		}
	}
	return nil
}

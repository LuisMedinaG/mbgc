package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	jwtlib "github.com/golang-jwt/jwt/v5"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
	"github.com/LuisMedinaG/mbgc/services/gateway/internal/config"
)

func main() {
	cfg := config.Load()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	verifier, err := newTokenVerifier(ctx, cfg)
	if err != nil {
		slog.Error("failed to initialize token verifier", "error", err)
		os.Exit(1)
	}
	protect := requireAuth(verifier)

	mux := http.NewServeMux()

	mux.Handle("/api/v1/auth/", proxy(cfg.AuthServiceURL))
	mux.Handle("/api/v1/games/", protect(proxy(cfg.GameServiceURL)))
	mux.Handle("/api/v1/collections/", protect(proxy(cfg.GameServiceURL)))
	mux.Handle("/api/v1/discover", protect(proxy(cfg.GameServiceURL)))
	mux.Handle("/api/v1/profile/", protect(proxy(cfg.AuthServiceURL)))
	mux.Handle("/api/v1/import/", protect(proxy(cfg.ImporterServiceURL)))

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		httpx.WriteJSON(w, http.StatusOK, envelope.New(map[string]string{"status": "ok"}))
	})

	handler := httpx.Chain(mux,
		httpx.Logger,
		httpx.RequestID,
		httpx.Recover,
		httpx.SecurityHeaders,
		httpx.CORS([]string{cfg.AllowedOrigin}),
	)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("gateway starting", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("shutdown error", "error", err)
	}
	slog.Info("gateway stopped")
}

// --- JWT claims ---

type supabaseClaims struct {
	jwtlib.RegisteredClaims
	Email        string                 `json:"email"`
	Role         string                 `json:"role"`
	AppMetadata  map[string]interface{} `json:"app_metadata"`
	UserMetadata map[string]interface{} `json:"user_metadata"`
}

func (c *supabaseClaims) username() string {
	if c.UserMetadata != nil {
		if v, ok := c.UserMetadata["username"].(string); ok && v != "" {
			return v
		}
	}
	return c.Email
}

func (c *supabaseClaims) isAdmin() bool {
	if c.AppMetadata != nil {
		if v, ok := c.AppMetadata["is_admin"].(bool); ok {
			return v
		}
	}
	return false
}

// --- Token verifier ---

// Supabase access tokens carry aud="authenticated". anon/service_role API
// keys use other roles and are intentionally rejected as user bearer tokens.
const supabaseAudience = "authenticated"

// tokenVerifier validates Supabase JWTs. The primary path is asymmetric
// ES256/RS256, where Supabase signs with a private key and the gateway fetches
// only public keys from the project's JWKS endpoint (auto-refreshed). HS256 is
// supported as a legacy fallback only when SUPABASE_JWT_SECRET is set, to keep
// verifying still-valid tokens issued before the migration to signing keys.
type tokenVerifier struct {
	keyfunc jwtlib.Keyfunc
	issuer  string
}

func newTokenVerifier(ctx context.Context, cfg config.Config) (*tokenVerifier, error) {
	issuer := strings.TrimSuffix(cfg.SupabaseURL, "/") + "/auth/v1"
	jwksURL := issuer + "/.well-known/jwks.json"

	jwks, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("init JWKS from %s: %w", jwksURL, err)
	}

	secret := []byte(cfg.JWTSecret)
	if len(secret) == 0 {
		slog.Info("HS256 disabled — no SUPABASE_JWT_SECRET set; verifying ES256/RS256 via JWKS only", "jwks", jwksURL)
	} else {
		slog.Info("HS256 legacy fallback enabled alongside JWKS", "jwks", jwksURL)
	}

	kf := func(t *jwtlib.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwtlib.SigningMethodHMAC); ok {
			if len(secret) == 0 {
				return nil, fmt.Errorf("HS256 token rejected: no legacy SUPABASE_JWT_SECRET configured")
			}
			return secret, nil
		}
		return jwks.Keyfunc(t)
	}

	return &tokenVerifier{keyfunc: kf, issuer: issuer}, nil
}

func (v *tokenVerifier) parse(tokenStr string) (*supabaseClaims, error) {
	token, err := jwtlib.ParseWithClaims(tokenStr, &supabaseClaims{}, v.keyfunc,
		jwtlib.WithValidMethods([]string{"ES256", "RS256", "HS256"}),
		jwtlib.WithIssuer(v.issuer),
		jwtlib.WithAudience(supabaseAudience),
		jwtlib.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*supabaseClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return claims, nil
}

// --- Middleware ---

func requireAuth(v *tokenVerifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			auth := r.Header.Get("Authorization")
			if !strings.HasPrefix(auth, "Bearer ") {
				httpx.WriteJSON(w, http.StatusUnauthorized,
					envelope.NewError(apierr.CodeUnauthorized, "missing or malformed token"))
				return
			}
			claims, err := v.parse(strings.TrimPrefix(auth, "Bearer "))
			if err != nil {
				httpx.WriteJSON(w, http.StatusUnauthorized,
					envelope.NewError(apierr.CodeUnauthorized, "invalid token"))
				return
			}
			r.Header.Set("X-User-ID", claims.Subject)
			r.Header.Set("X-Username", claims.username())
			if claims.isAdmin() {
				r.Header.Set("X-Is-Admin", "true")
			} else {
				r.Header.Del("X-Is-Admin")
			}
			next.ServeHTTP(w, r)
		})
	}
}

func proxy(target string) http.Handler {
	u, err := url.Parse(target)
	if err != nil {
		panic(fmt.Sprintf("invalid proxy target %q: %v", target, err))
	}
	return httputil.NewSingleHostReverseProxy(u)
}

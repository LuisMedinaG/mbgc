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

	jwtlib "github.com/golang-jwt/jwt/v5"

	"github.com/LuisMedinaG/mbgc/services/gateway/internal/config"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

func main() {
	cfg := config.Load()
	protect := requireAuth(cfg.JWTSecret)

	mux := http.NewServeMux()

	// Public — no JWT required
	mux.Handle("/api/v1/auth/", proxy(cfg.AuthServiceURL))

	// Protected — JWT validated, identity headers forwarded to services
	mux.Handle("/api/v1/games/", protect(proxy(cfg.GameServiceURL)))
	mux.Handle("/api/v1/collections/", protect(proxy(cfg.GameServiceURL)))
	mux.Handle("/api/v1/discover", protect(proxy(cfg.GameServiceURL)))
	mux.Handle("/api/v1/profile/", protect(proxy(cfg.AuthServiceURL)))
	mux.Handle("/api/v1/import/", protect(proxy(cfg.ImporterServiceURL)))

	// Health check — used by Fly.io and load balancers
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

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("shutdown error", "error", err)
	}
	slog.Info("gateway stopped")
}

// supabaseClaims maps the JWT claims issued by Supabase Auth.
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

func parseToken(tokenStr, secret string) (*supabaseClaims, error) {
	token, err := jwtlib.ParseWithClaims(tokenStr, &supabaseClaims{}, func(t *jwtlib.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwtlib.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return []byte(secret), nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*supabaseClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return claims, nil
}

// requireAuth validates a Supabase JWT and injects identity headers for downstream services.
func requireAuth(secret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			auth := r.Header.Get("Authorization")
			if !strings.HasPrefix(auth, "Bearer ") {
				httpx.WriteJSON(w, http.StatusUnauthorized,
					envelope.NewError(apierr.CodeUnauthorized, "missing or malformed token"))
				return
			}
			claims, err := parseToken(strings.TrimPrefix(auth, "Bearer "), secret)
			if err != nil {
				httpx.WriteJSON(w, http.StatusUnauthorized,
					envelope.NewError(apierr.CodeUnauthorized, "invalid token"))
				return
			}
			// Inject identity — internal services read these via httpx.TrustGatewayHeaders
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

// proxy returns a reverse proxy to the given base URL.
func proxy(target string) http.Handler {
	u, err := url.Parse(target)
	if err != nil {
		panic(fmt.Sprintf("invalid proxy target %q: %v", target, err))
	}
	return httputil.NewSingleHostReverseProxy(u)
}

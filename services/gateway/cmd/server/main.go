package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
	"github.com/LuisMedinaG/mbgc/services/gateway/internal/config"
)

func main() {
	cfg := config.Load()
	protect := requireAuth(cfg)

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

// --- JWT types ---

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

// --- Token verifier (HS256 + ES256/RS256 via JWKS) ---

type tokenVerifier struct {
	secret  string
	jwksURL string
	jwks    map[string]interface{} // kid → public key
	jwksMu  sync.RWMutex
	fetched bool
}

func newTokenVerifier(cfg config.Config) *tokenVerifier {
	return &tokenVerifier{
		secret:  cfg.JWTSecret,
		jwksURL: strings.TrimSuffix(cfg.SupabaseURL, "/") + "/auth/v1/.well-known/jwks.json",
		jwks:    make(map[string]interface{}),
	}
}

func (v *tokenVerifier) keyfunc(t *jwtlib.Token) (interface{}, error) {
	// HS256 / HS384 / HS512 — shared secret
	if _, ok := t.Method.(*jwtlib.SigningMethodHMAC); ok {
		return []byte(v.secret), nil
	}

	// RS256 / ES256 — fetch public key from Supabase JWKS
	kid, ok := t.Header["kid"].(string)
	if !ok {
		return nil, fmt.Errorf("missing kid in JWT header (non-HMAC token)")
	}

	v.jwksMu.RLock()
	key, exists := v.jwks[kid]
	ok = exists
	v.jwksMu.RUnlock()
	if ok {
		return key, nil
	}

	if err := v.fetchJWKS(); err != nil {
		return nil, fmt.Errorf("jwks fetch: %w", err)
	}

	v.jwksMu.RLock()
	key, exists = v.jwks[kid]
	v.jwksMu.RUnlock()
	if !exists {
		return nil, fmt.Errorf("kid %q not found in JWKS", kid)
	}
	return key, nil
}

func (v *tokenVerifier) fetchJWKS() error {
	resp, err := http.Get(v.jwksURL)
	if err != nil {
		return fmt.Errorf("GET %s: %w", v.jwksURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("JWKS returned %d", resp.StatusCode)
	}

	var set struct {
		Keys []json.RawMessage `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return fmt.Errorf("decode JWKS: %w", err)
	}

	v.jwksMu.Lock()
	defer v.jwksMu.Unlock()

	for _, raw := range set.Keys {
		var jwk struct {
			KID string `json:"kid"`
			KTY string `json:"kty"`
			N   string `json:"n"`
			E   string `json:"e"`
			CRV string `json:"crv"`
			X   string `json:"x"`
			Y   string `json:"y"`
		}
		if err := json.Unmarshal(raw, &jwk); err != nil || jwk.KID == "" {
			continue
		}
		if _, exists := v.jwks[jwk.KID]; exists {
			continue
		}

		var pubKey interface{}
		switch jwk.KTY {
		case "EC":
			pubKey, err = parseECKey(jwk.CRV, jwk.X, jwk.Y)
		case "RSA":
			pubKey, err = parseRSAKey(jwk.N, jwk.E)
		default:
			continue
		}
		if err != nil {
			slog.Warn("failed to parse JWK", "kid", jwk.KID, "error", err)
			continue
		}
		v.jwks[jwk.KID] = pubKey
	}

	v.fetched = true
	return nil
}

func parseECKey(crv, xb64, yb64 string) (*ecdsa.PublicKey, error) {
	var curve elliptic.Curve
	switch crv {
	case "P-256":
		curve = elliptic.P256()
	case "P-384":
		curve = elliptic.P384()
	case "P-521":
		curve = elliptic.P521()
	default:
		return nil, fmt.Errorf("unknown EC curve: %s", crv)
	}

	x, err := b64Decode(xb64)
	if err != nil {
		return nil, err
	}
	y, err := b64Decode(yb64)
	if err != nil {
		return nil, err
	}

	return &ecdsa.PublicKey{
		Curve: curve,
		X:     new(big.Int).SetBytes(x),
		Y:     new(big.Int).SetBytes(y),
	}, nil
}

func parseRSAKey(nb64, eb64 string) (*rsa.PublicKey, error) {
	n, err := b64Decode(nb64)
	if err != nil {
		return nil, err
	}
	e, err := b64Decode(eb64)
	if err != nil {
		return nil, err
	}

	return &rsa.PublicKey{
		N: new(big.Int).SetBytes(n),
		E: int(new(big.Int).SetBytes(e).Int64()),
	}, nil
}

func b64Decode(s string) ([]byte, error) {
	// JWK uses base64url without padding — add padding for Go's decoder
	s = strings.TrimRight(s, "=")
	switch len(s) % 4 {
	case 2:
		s += "=="
	case 3:
		s += "="
	}
	return base64.URLEncoding.DecodeString(s)
}

// --- Parse token ---

func parseToken(tokenStr string, v *tokenVerifier) (*supabaseClaims, error) {
	token, err := jwtlib.ParseWithClaims(tokenStr, &supabaseClaims{}, v.keyfunc,
		jwtlib.WithValidMethods([]string{"HS256", "HS384", "HS512", "RS256", "ES256"}),
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

func requireAuth(cfg config.Config) func(http.Handler) http.Handler {
	v := newTokenVerifier(cfg)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			auth := r.Header.Get("Authorization")
			if !strings.HasPrefix(auth, "Bearer ") {
				httpx.WriteJSON(w, http.StatusUnauthorized,
					envelope.NewError(apierr.CodeUnauthorized, "missing or malformed token"))
				return
			}
			claims, err := parseToken(strings.TrimPrefix(auth, "Bearer "), v)
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

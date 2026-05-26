package jwt

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/MicahParks/keyfunc/v3"
	jwtlib "github.com/golang-jwt/jwt/v5"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// sub: auth.JWT_VALIDATION.7 — validates aud claim = "authenticated"
// sub: auth.JWT_VALIDATION.8 — rejects anon/service_role API keys
const supabaseAudience = "authenticated"

type claims struct {
	jwtlib.RegisteredClaims
	Email        string                 `json:"email"`
	Role         string                 `json:"role"`
	AppMetadata  map[string]interface{} `json:"app_metadata"`
	UserMetadata map[string]interface{} `json:"user_metadata"`
}

func (c *claims) username() string {
	if c.UserMetadata != nil {
		if v, ok := c.UserMetadata["username"].(string); ok && v != "" {
			return v
		}
	}
	return c.Email
}

func (c *claims) isAdmin() bool {
	if c.AppMetadata != nil {
		if v, ok := c.AppMetadata["is_admin"].(bool); ok {
			return v
		}
	}
	return false
}

// Verifier validates Supabase JWTs.
// Primary path: ES256/RS256 via JWKS (auto-refreshed, public keys only).
// Legacy path: HS256 via SUPABASE_JWT_SECRET (only when explicitly set).
type Verifier struct {
	keyfunc jwtlib.Keyfunc
	issuer  string
}

// NewVerifier initialises the JWKS client and returns a ready Verifier.
// ref: auth.JWT_VALIDATION.1 — fetches JWKS at boot
// ref: auth.JWT_VALIDATION.2 — auto-refreshes via keyfunc/v3
// ref: auth.JWT_VALIDATION.3 — validates ES256/RS256 signatures
// ref: auth.JWT_VALIDATION.4 — optional HS256 legacy fallback
func NewVerifier(ctx context.Context, supabaseURL, jwtSecret string) (*Verifier, error) {
	issuer := strings.TrimSuffix(supabaseURL, "/") + "/auth/v1"
	jwksURL := issuer + "/.well-known/jwks.json"

	jwks, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("init JWKS from %s: %w", jwksURL, err)
	}

	secret := []byte(jwtSecret)
	if len(secret) == 0 {
		slog.Info("HS256 disabled — verifying ES256/RS256 via JWKS only", "jwks", jwksURL)
	} else {
		slog.Info("HS256 legacy fallback enabled alongside JWKS", "jwks", jwksURL)
	}

	kf := func(t *jwtlib.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwtlib.SigningMethodHMAC); ok {
			if len(secret) == 0 {
				return nil, fmt.Errorf("HS256 token rejected: SUPABASE_JWT_SECRET not configured")
			}
			return secret, nil
		}
		return jwks.Keyfunc(t)
	}

	return &Verifier{keyfunc: kf, issuer: issuer}, nil
}

// ref: auth.JWT_VALIDATION.5 — validates exp claim
// ref: auth.JWT_VALIDATION.6 — validates iss claim
// ref: auth.JWT_VALIDATION.7 — validates aud claim
func (v *Verifier) parse(tokenStr string) (*claims, error) {
	token, err := jwtlib.ParseWithClaims(tokenStr, &claims{}, v.keyfunc,
		jwtlib.WithValidMethods([]string{"ES256", "RS256", "HS256"}),
		jwtlib.WithIssuer(v.issuer),
		jwtlib.WithAudience(supabaseAudience),
		jwtlib.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}
	c, ok := token.Claims.(*claims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return c, nil
}

// RequireAuth is middleware that validates the Bearer JWT and populates context.
// ref: auth.JWT_VALIDATION.9 — extracts user identity into request context
// ref: auth.JWT_VALIDATION.10 — returns 401 for any validation failure
// ref: profile.ADMIN.3 — admin flag available via httpx.IsAdminFromContext
func (v *Verifier) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			httpx.WriteJSON(w, http.StatusUnauthorized,
				envelope.NewError(apierr.CodeUnauthorized, "missing or malformed token"))
			return
		}
		c, err := v.parse(strings.TrimPrefix(auth, "Bearer "))
		if err != nil {
			httpx.WriteJSON(w, http.StatusUnauthorized,
				envelope.NewError(apierr.CodeUnauthorized, "invalid token"))
			return
		}
		ctx := httpx.SetGatewayUser(r.Context(), c.Subject, c.username(), c.isAdmin())
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

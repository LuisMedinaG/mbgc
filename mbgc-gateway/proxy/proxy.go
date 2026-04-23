package proxy

import (
	"net/http"
	"net/http/httputil"
	"net/url"

	"github.com/luismedinag/mbgc-shared/middleware"
)

// hopByHopHeaders are headers that should not be forwarded to the upstream.
// net/http already strips most of these, but we remove them explicitly for clarity.
var hopByHopHeaders = []string{
	"Connection",
	"Keep-Alive",
	"Proxy-Authenticate",
	"Proxy-Authorization",
	"TE",
	"Trailers",
	"Transfer-Encoding",
	"Upgrade",
}

// New returns an http.Handler that reverse-proxies requests to target.
// If JWT claims are present in the request context (populated by the Auth or
// OptionalAuth middleware), the corresponding X-User-* headers are injected
// before the request is forwarded.
func New(target string) http.Handler {
	u, err := url.Parse(target)
	if err != nil {
		panic("proxy: invalid target URL: " + err.Error())
	}

	rp := httputil.NewSingleHostReverseProxy(u)

	// Replace the default Director so we have full control over header handling.
	defaultDirector := rp.Director
	rp.Director = func(req *http.Request) {
		// Let the stdlib director set Host, URL scheme/host, and X-Forwarded-For.
		defaultDirector(req)

		// Remove hop-by-hop headers.
		for _, h := range hopByHopHeaders {
			req.Header.Del(h)
		}

		// Inject user identity headers from JWT claims (if present).
		if claims := middleware.GetClaims(req); claims != nil {
			req.Header.Set("X-User-ID", claims.UserID)
			req.Header.Set("X-User-Email", claims.Email)
			req.Header.Set("X-User-Role", claims.Role)
		}
	}

	return rp
}

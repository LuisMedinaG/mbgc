package httpx

import (
	"mime"
	"net/http"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
)

// RequireContentType rejects body-bearing requests whose Content-Type is not in the allowed list.
// Requests without a detected body pass through unconditionally, so GET/DELETE/OPTIONS/HEAD
// are never affected. This closes the text/plain CSRF bypass on mutating routes.
//
// ref: api-layer.SEC.7 — enforces declared Content-Type on body-bearing requests
func RequireContentType(allowed ...string) func(http.Handler) http.Handler {
	allowedSet := make(map[string]struct{}, len(allowed))
	for _, a := range allowed {
		allowedSet[strings.ToLower(a)] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if requestHasBody(r) {
				ct, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
				if _, ok := allowedSet[strings.ToLower(ct)]; !ok {
					WriteError(w, apierr.ErrUnsupportedMediaType)
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// requestHasBody returns true when the request carries a non-empty body.
func requestHasBody(r *http.Request) bool {
	return r.ContentLength > 0 ||
		(r.ContentLength < 0 && r.Body != nil && r.Body != http.NoBody)
}

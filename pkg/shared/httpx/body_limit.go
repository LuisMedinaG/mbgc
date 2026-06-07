package httpx

import (
	"net/http"
)

// LimitBodySize returns middleware that caps the request body at maxBytes.
// Exceeding the limit causes json.Decode to fail with "http: request body too large".
// ref: api-layer.SEC.6 — prevents memory exhaustion from large request bodies
func LimitBodySize(maxBytes int64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
			next.ServeHTTP(w, r)
		})
	}
}

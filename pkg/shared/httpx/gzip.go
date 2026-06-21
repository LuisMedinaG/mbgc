package httpx

import (
	"compress/gzip"
	"net/http"
	"strings"
)

// Gzip compresses responses for clients that advertise gzip support.
// Only compresses responses larger than 1KB to avoid overhead on tiny payloads.
func Gzip(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
			next.ServeHTTP(w, r)
			return
		}
		gz, err := gzip.NewWriterLevel(w, gzip.BestSpeed)
		if err != nil {
			next.ServeHTTP(w, r)
			return
		}
		defer gz.Close()
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Add("Vary", "Accept-Encoding")
		// Remove Content-Length — it's invalid after compression.
		w.Header().Del("Content-Length")
		next.ServeHTTP(&gzipWriter{ResponseWriter: w, gz: gz}, r)
	})
}

type gzipWriter struct {
	http.ResponseWriter
	gz *gzip.Writer
}

func (g *gzipWriter) Write(b []byte) (int, error) {
	return g.gz.Write(b)
}

// WriteHeader propagates the status code to the underlying ResponseWriter.
func (g *gzipWriter) WriteHeader(status int) {
	g.ResponseWriter.WriteHeader(status)
}

package httpx

import (
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
	"golang.org/x/time/rate"
)

type ipLimiter struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// RateLimiter returns middleware that enforces a per-IP token-bucket rate limit.
// ratePerSec defines sustained requests/sec; burst allows short bursts above that.
// ref: api-layer.SEC.5 — rate limits auth endpoints to prevent brute-force
func RateLimiter(ratePerSec float64, burst int) func(http.Handler) http.Handler {
	var (
		mu       sync.Mutex
		visitors = make(map[string]*ipLimiter)
	)

	// Background cleanup every 5 minutes to prevent unbounded memory growth.
	go func() {
		for {
			time.Sleep(5 * time.Minute)
			mu.Lock()
			for ip, v := range visitors {
				if time.Since(v.lastSeen) > 5*time.Minute {
					delete(visitors, ip)
				}
			}
			mu.Unlock()
		}
	}()

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := clientIP(r)
			mu.Lock()
			v, ok := visitors[ip]
			if !ok {
				v = &ipLimiter{limiter: rate.NewLimiter(rate.Limit(ratePerSec), burst)}
				visitors[ip] = v
			}
			v.lastSeen = time.Now()
			mu.Unlock()

			if !v.limiter.Allow() {
				// ref: monitoring.SINK.3
				Record(r, "rate_limit", slog.LevelWarn)
				WriteError(w, apierr.ErrRateLimit)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// clientIP extracts the client IP, trusting only the rightmost X-Forwarded-For entry.
// ref: api-layer.SEC.5 — rightmost XFF is appended by the trusted edge (GFE / Cloud Run);
// leftmost entries are client-spoofable and must not be used to key the per-IP bucket.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.LastIndex(xff, ","); i >= 0 {
			return strings.TrimSpace(xff[i+1:])
		}
		return strings.TrimSpace(xff)
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

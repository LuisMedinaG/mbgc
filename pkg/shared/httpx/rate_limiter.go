package httpx

import (
	"net/http"
	"sync"
	"time"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
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
				WriteError(w, apierr.ErrRateLimit)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// clientIP extracts the client IP, respecting X-Forwarded-For when behind a proxy.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// Take the leftmost (original client) IP.
		for i := 0; i < len(xff); i++ {
			if xff[i] == ',' {
				return xff[:i]
			}
		}
		return xff
	}
	// Fall back to RemoteAddr; strip port.
	addr := r.RemoteAddr
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[:i]
		}
	}
	return addr
}

// Package httpx provides HTTP middleware and context utilities for mbgc services.
package httpx

import (
	"net/http"
	"time"
)

// DefaultClient is an http.Client with sensible timeouts for outbound calls
// (Supabase Auth API, BGG API). Use this instead of http.DefaultClient which
// has no timeout and can exhaust goroutines on a hung upstream.
// ref: api-layer.SEC.4 — shared HTTP client with 10s timeout
var DefaultClient = &http.Client{
	Timeout: 10 * time.Second,
}

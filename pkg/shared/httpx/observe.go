package httpx

import (
	"context"
	"log/slog"
	"net/http"
	"sync/atomic"
)

// allowedAttrs is the single source of truth for fields that may appear on
// a monitored event. Any key passed to Record that is not in this map is
// silently dropped before the event reaches the slog handler.
//
// The function signature does not accept a header map, body, or query string
// — that is the structural guarantee that PII and secrets stay out of the
// sink. The map below is the second line of defense.
//
// ref: monitoring.REDACTION.5
var allowedAttrs = map[string]struct{}{
	"request_id": {}, // helper-managed (always set, last-write-wins)
	"method":     {}, // helper-managed
	"path":       {}, // helper-managed
	"event":      {}, // helper-managed
	"status":     {},
	"latency_ms": {},
	"error_code": {},
	"stack":      {},
	"sync_kind":  {},
	"game_count": {},
}

// Disabled is a kill switch for the entire monitoring pipeline. When true,
// Record returns immediately without emitting anything, dropping Cloud
// Logging ingestion to zero from this service (and starving the log-based
// metrics, which stops the alert policies from firing).
//
// Set once at startup by main() from the MONITORING_DISABLED env var. Read
// on every Record call via the atomic, so flipping the env var on the next
// service deploy takes effect without any code change.
//
// ref: monitoring.OBSERVABILITY.3
var Disabled atomic.Bool

// Record emits a structured event through slog. The event is guaranteed to
// carry request_id, method, path, and event name. Any caller-supplied
// attribute whose key is not in allowedAttrs is silently dropped.
//
// The function is the only sanctioned way to emit a monitored event from
// request handling code. Centralizing emission here means the allow-list
// cannot be bypassed by a careless call site.
//
// ref: monitoring.SINK.6, monitoring.SINK.7, monitoring.REDACTION.1-4
func Record(r *http.Request, event string, level slog.Level, attrs ...any) {
	// ref: monitoring.OBSERVABILITY.3 — kill switch short-circuits before any work
	if Disabled.Load() {
		return
	}

	// Caller attrs are filtered first. Anything not in the allow-list is
	// dropped before it can influence the emitted event.
	filtered := filterAttrs(attrs)

	// status and latency_ms are part of the monitoring contract
	// (monitoring.SINK.6). Defaults are injected here so caller-supplied
	// non-request events (panic, rate_limit, sync_*) still serialize with
	// the canonical field set, and downstream metrics can group_by on them.
	// ref: monitoring.SINK.6 — status/latency_ms always present
	if !hasAttrKey(attrs, "status") {
		filtered = append(filtered, slog.Int("status", 0))
	}
	if !hasAttrKey(attrs, "latency_ms") {
		filtered = append(filtered, slog.Int64("latency_ms", 0))
	}

	// Helper-managed fields are appended last so they win any same-key
	// collision in slog's last-write-wins JSON output, defending against
	// a caller that re-injects a reserved key through attrs.
	args := filtered
	if r != nil {
		args = append(args,
			slog.String("request_id", RequestIDFromContext(r.Context())),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
		)
	}
	args = append(args, slog.String("event", event))

	ctx := context.Background()
	if r != nil {
		ctx = r.Context()
	}
	slog.Log(ctx, level, event, args...)
}

// filterAttrs walks a slog-style key/value list and returns only pairs whose
// key is in allowedAttrs. Odd-length inputs have the trailing key dropped.
func filterAttrs(attrs []any) []any {
	out := make([]any, 0, len(attrs))
	for i := 0; i+1 < len(attrs); i += 2 {
		key, ok := attrs[i].(string)
		if !ok {
			continue
		}
		if _, allowed := allowedAttrs[key]; !allowed {
			continue
		}
		out = append(out, slog.Any(key, attrs[i+1]))
	}
	return out
}

// hasAttrKey reports whether attrs (a slog-style key/value list) contains a
// pair with the given key. Used to default-inject required monitoring fields
// when the caller did not supply them.
func hasAttrKey(attrs []any, key string) bool {
	for i := 0; i+1 < len(attrs); i += 2 {
		if k, ok := attrs[i].(string); ok && k == key {
			return true
		}
	}
	return false
}

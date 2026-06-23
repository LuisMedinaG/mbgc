package httpx

import (
	"context"
	"log/slog"
	"net/http"
)

// Disabled is a kill switch for the entire monitoring pipeline. Set once at
// startup from MONITORING_DISABLED; Record becomes a no-op when true.
var Disabled bool

// Record emits a structured event through slog. Guaranteed to carry
// request_id, method, path, and event name when r is non-nil.
// status and latency_ms default to 0 when not supplied by the caller.
// Odd-length attr lists and non-string keys are silently dropped so slog's
// arg-pairing is never misaligned.
func Record(r *http.Request, event string, level slog.Level, attrs ...any) {
	if Disabled {
		return
	}

	hasStatus, hasLatency := false, false
	args := make([]any, 0, len(attrs)+6)
	for i := 0; i+1 < len(attrs); i += 2 {
		k, ok := attrs[i].(string)
		if !ok {
			continue
		}
		args = append(args, k, attrs[i+1])
		if k == "status" {
			hasStatus = true
		}
		if k == "latency_ms" {
			hasLatency = true
		}
	}

	if !hasStatus {
		args = append(args, slog.Int("status", 0))
	}
	if !hasLatency {
		args = append(args, slog.Int64("latency_ms", 0))
	}

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

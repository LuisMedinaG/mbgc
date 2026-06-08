// Package observe wires the API's logging path: a fail-open slog handler that
// emits JSON to stdout (Cloud Logging ingests stdout in Cloud Run) and a
// background heartbeat that proves the service is alive.
package observe

import (
	"context"
	"io"
	"log/slog"
	"os"
	"time"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// NewHandler returns a slog handler that:
//   - writes JSON to stdout for Cloud Logging to ingest
//   - is fail-open: a handler-level error never propagates to the caller
//   - emits an event=meta_warning to stderr (separate sink) when the primary
//     write fails, so we can see in logs that the monitoring path itself broke
//
// ref: monitoring.OBSERVABILITY.1, monitoring.FAIL_OPEN.1, monitoring.FAIL_OPEN.2
func NewHandler() slog.Handler {
	return newFailOpen(os.Stdout, os.Stderr, slog.LevelInfo)
}

// ref: monitoring.FAIL_OPEN.1, monitoring.FAIL_OPEN.2 — testable fail-open constructor
// newFailOpen is the testable constructor.
func newFailOpen(primary, meta io.Writer, level slog.Level) slog.Handler {
	return &failOpenHandler{
		primary: slog.NewJSONHandler(primary, &slog.HandlerOptions{Level: level}),
		meta:    slog.NewJSONHandler(meta, &slog.HandlerOptions{Level: slog.LevelWarn}),
	}
}

// ref: monitoring.FAIL_OPEN.1, monitoring.FAIL_OPEN.2 — failOpenHandler splits primary/meta sinks
type failOpenHandler struct {
	primary slog.Handler
	meta    slog.Handler
}

// ref: monitoring.FAIL_OPEN.1 — defer Enabled to the primary sink
func (h *failOpenHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.primary.Enabled(ctx, level)
}

// ref: monitoring.FAIL_OPEN.1, monitoring.FAIL_OPEN.2, monitoring.OBSERVABILITY.1 —
// primary failure never propagates; meta_warning is emitted to the meta sink
func (h *failOpenHandler) Handle(ctx context.Context, r slog.Record) error {
	if err := h.primary.Handle(ctx, r); err != nil {
		// Best-effort meta-warning. The meta handler is on a different sink
		// (stderr) so it survives a broken stdout pipe. If the meta write
		// itself fails, we drop it — the fail-open contract is "never block
		// the caller", not "never lose visibility".
		warnRec := slog.NewRecord(time.Now(), slog.LevelWarn, "meta_warning", r.PC)
		warnRec.AddAttrs(
			slog.String("event", "meta_warning"),
			slog.String("cause", err.Error()),
		)
		_ = h.meta.Handle(ctx, warnRec)
		return nil
	}
	return nil
}

// ref: monitoring.FAIL_OPEN.1 — WithAttrs threads attrs through the primary sink only
func (h *failOpenHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &failOpenHandler{primary: h.primary.WithAttrs(attrs), meta: h.meta}
}

// ref: monitoring.FAIL_OPEN.1 — WithGroup threads grouping through the primary sink only
func (h *failOpenHandler) WithGroup(name string) slog.Handler {
	return &failOpenHandler{primary: h.primary.WithGroup(name), meta: h.meta}
}

// Heartbeat emits a single event=heartbeat record, then ticks every `interval`
// until ctx is cancelled. Intended to run as a goroutine at service startup.
//
// ref: monitoring.OBSERVABILITY.2
func Heartbeat(ctx context.Context, interval time.Duration) {
	emitHeartbeat()
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			emitHeartbeat()
		}
	}
}

// ref: monitoring.OBSERVABILITY.2 — emit a single heartbeat event via the shared sink
func emitHeartbeat() {
	httpx.Record(nil, "heartbeat", slog.LevelInfo)
}

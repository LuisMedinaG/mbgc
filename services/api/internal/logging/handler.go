// Package logging wires the API's slog handler and background heartbeat.
package logging

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// NewHandler returns a JSON slog handler writing to stdout for Cloud Logging.
// ref: monitoring.OBSERVABILITY.1
func NewHandler() slog.Handler {
	return slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
}

// Heartbeat emits event=heartbeat on start then every interval until ctx is cancelled.
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

func emitHeartbeat() {
	httpx.Record(nil, "heartbeat", slog.LevelInfo)
}

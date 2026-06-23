package httpx

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"
)

// captureSlog swaps slog.Default to a JSON handler writing to a buffer for
// the duration of the test, then restores the previous default.
func captureSlog(t *testing.T) *bytes.Buffer {
	t.Helper()
	buf := &bytes.Buffer{}
	prev := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(buf, &slog.HandlerOptions{Level: slog.LevelInfo})))
	t.Cleanup(func() { slog.SetDefault(prev) })
	return buf
}

// decodeLine parses a single JSON line from buf.
func decodeLine(t *testing.T, buf *bytes.Buffer) map[string]any {
	t.Helper()
	raw := strings.TrimRight(buf.String(), "\n")
	if raw == "" {
		t.Fatal("expected a log line, got empty")
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("failed to parse log line %q: %v", raw, err)
	}
	return m
}

// ref: monitoring.SINK.6, monitoring.REDACTION.5 — helper always sets the
// required fields, regardless of what the caller passes
func TestRecord_IncludesRequestIDMethodPath(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("POST", "/api/v1/games/bulk-collections", nil)
	r = r.WithContext(withRequestID(r.Context(), "req-123"))

	Record(r, "request", slog.LevelInfo)

	rec := decodeLine(t, buf)
	if rec["request_id"] != "req-123" {
		t.Errorf("expected request_id=req-123, got %v", rec["request_id"])
	}
	if rec["method"] != "POST" {
		t.Errorf("expected method=POST, got %v", rec["method"])
	}
	if rec["path"] != "/api/v1/games/bulk-collections" {
		t.Errorf("expected path=/api/v1/games/bulk-collections, got %v", rec["path"])
	}
	if rec["event"] != "request" {
		t.Errorf("expected event=request, got %v", rec["event"])
	}
	if rec["msg"] != "request" {
		t.Errorf("expected slog msg=request, got %v", rec["msg"])
	}
}

// ref: monitoring.SINK.6, monitoring.REDACTION.5 — caller-supplied reserved
// keys cannot override the helper-managed values (last-write-wins defense)
func TestRecord_HelperFieldsOverrideCallerInjection(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/api/v1/games", nil)
	r = r.WithContext(withRequestID(r.Context(), "real-id"))

	Record(r, "test_event", slog.LevelInfo,
		"request_id", "forged-id",
		"method", "EVIL",
		"path", "/forged",
		"event", "forged_event",
	)

	rec := decodeLine(t, buf)
	if rec["request_id"] != "real-id" {
		t.Errorf("caller overrode request_id, got %v", rec["request_id"])
	}
	if rec["method"] != "GET" {
		t.Errorf("caller overrode method, got %v", rec["method"])
	}
	if rec["path"] != "/api/v1/games" {
		t.Errorf("caller overrode path, got %v", rec["path"])
	}
	if rec["event"] != "test_event" {
		t.Errorf("caller overrode event, got %v", rec["event"])
	}
}

// ref: monitoring.SINK.6 — optional allow-list keys pass through verbatim
func TestRecord_AllowsKnownOptionalKeys(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/api/v1/games", nil)

	Record(r, "panic", slog.LevelError,
		"status", 500,
		"latency_ms", 42,
		"error_code", "INTERNAL_ERROR",
		"stack", "goroutine 1 [running]:...",
	)

	rec := decodeLine(t, buf)
	if rec["status"] != float64(500) {
		t.Errorf("expected status=500, got %v", rec["status"])
	}
	if rec["latency_ms"] != float64(42) {
		t.Errorf("expected latency_ms=42, got %v", rec["latency_ms"])
	}
	if rec["error_code"] != "INTERNAL_ERROR" {
		t.Errorf("expected error_code=INTERNAL_ERROR, got %v", rec["error_code"])
	}
	if rec["stack"] != "goroutine 1 [running]:..." {
		t.Errorf("expected stack, got %v", rec["stack"])
	}
}

// ref: monitoring.SINK.5 — BGG sync fields pass through
func TestRecord_AllowsSyncFields(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("POST", "/api/v1/import/sync", nil)

	Record(r, "sync_ok", slog.LevelInfo,
		"sync_kind", "incremental",
		"game_count", 17,
	)

	rec := decodeLine(t, buf)
	if rec["sync_kind"] != "incremental" {
		t.Errorf("expected sync_kind=incremental, got %v", rec["sync_kind"])
	}
	if rec["game_count"] != float64(17) {
		t.Errorf("expected game_count=17, got %v", rec["game_count"])
	}
}

// ref: monitoring.SINK.7 — odd-length attr lists are tolerated (trailing
// key is dropped, no panic)
func TestRecord_OddLengthAttrsTolerated(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/", nil)

	Record(r, "test_event", slog.LevelInfo, "status", 200, "stranded_key")

	rec := decodeLine(t, buf)
	if rec["status"] != float64(200) {
		t.Errorf("expected status=200, got %v", rec["status"])
	}
	if _, ok := rec["stranded_key"]; ok {
		t.Errorf("stranded key should be dropped, got %v", rec["stranded_key"])
	}
}

// ref: monitoring.SINK.7 — non-string keys are dropped, no panic
func TestRecord_NonStringKeysDropped(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/", nil)

	Record(r, "test_event", slog.LevelInfo, 42, "value", "status", 200)

	rec := decodeLine(t, buf)
	if rec["status"] != float64(200) {
		t.Errorf("expected status=200, got %v", rec["status"])
	}
	if _, ok := rec["42"]; ok {
		t.Errorf("non-string key should be dropped, got %v", rec["42"])
	}
}

// ref: monitoring.FAIL_OPEN.1 — nil request is tolerated (no panic, event
// still emitted with no request-derived fields)
func TestRecord_NilRequestSafe(t *testing.T) {
	buf := captureSlog(t)

	Record(nil, "heartbeat", slog.LevelInfo)

	rec := decodeLine(t, buf)
	if rec["event"] != "heartbeat" {
		t.Errorf("expected event=heartbeat, got %v", rec["event"])
	}
	if _, ok := rec["request_id"]; ok {
		t.Errorf("expected no request_id for nil request, got %v", rec["request_id"])
	}
	if _, ok := rec["path"]; ok {
		t.Errorf("expected no path for nil request, got %v", rec["path"])
	}
}

// ref: monitoring.SINK.6 — level flows through to the handler
func TestRecord_RespectsSlogLevel(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/", nil)

	Record(r, "test_warn", slog.LevelWarn)

	rec := decodeLine(t, buf)
	if rec["level"] != "WARN" {
		t.Errorf("expected level=WARN, got %v", rec["level"])
	}
}

// ref: monitoring.SINK.6 — query string is dropped (path is logged as-is)
func TestRecord_QueryStringNotInPath(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/api/v1/games?secret=true&page=2", nil)

	Record(r, "request", slog.LevelInfo)

	rec := decodeLine(t, buf)
	if rec["path"] != "/api/v1/games" {
		t.Errorf("expected path=/api/v1/games (no query), got %v", rec["path"])
	}
	if strings.Contains(buf.String(), "secret=true") {
		t.Errorf("query string leaked into log output: %s", buf.String())
	}
}

// ref: monitoring.SINK.6 — request context is forwarded to the slog handler
func TestRecord_ForwardsContext(t *testing.T) {
	type ctxKey struct{}
	ctx := context.WithValue(context.Background(), ctxKey{}, "marker")
	r := httptest.NewRequest("GET", "/", nil).WithContext(ctx)

	var seen context.Context
	rec := &ctxRecorder{seen: &seen}
	prev := slog.Default()
	slog.SetDefault(slog.New(rec))
	t.Cleanup(func() { slog.SetDefault(prev) })

	Record(r, "test_event", slog.LevelInfo)

	if seen.Value(ctxKey{}) != "marker" {
		t.Errorf("expected ctx forwarded to handler, got %v", seen.Value(ctxKey{}))
	}
}

// ref: monitoring.SINK.6 — every emitted event carries status and latency_ms
// (defaulted to 0 when the caller did not supply them)
func TestRecord_DefaultsStatusAndLatency(t *testing.T) {
	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/api/v1/games", nil)

	Record(r, "panic", slog.LevelError, "stack", "trace")

	rec := decodeLine(t, buf)
	if v, ok := rec["status"]; !ok {
		t.Errorf("expected status field present, got %v", rec)
	} else if v != float64(0) {
		t.Errorf("expected status=0 (default), got %v", v)
	}
	if v, ok := rec["latency_ms"]; !ok {
		t.Errorf("expected latency_ms field present, got %v", rec)
	} else if v != float64(0) {
		t.Errorf("expected latency_ms=0 (default), got %v", v)
	}
}

// ref: monitoring.OBSERVABILITY.3 — kill switch makes Record a no-op.
// Restores the prior Disabled state in Cleanup so it doesn't leak into
// other tests in the package.
func TestRecord_NoOpWhenDisabled(t *testing.T) {
	prev := Disabled
	t.Cleanup(func() { Disabled = prev })
	Disabled = true

	buf := captureSlog(t)
	r := httptest.NewRequest("GET", "/api/v1/games", nil)
	Record(r, "should_not_appear", slog.LevelInfo, "key", "value")

	if buf.Len() != 0 {
		t.Fatalf("expected zero output when Disabled=true, got %q", buf.String())
	}
}

type ctxRecorder struct {
	slog.Handler
	seen *context.Context
}

func (h *ctxRecorder) Enabled(context.Context, slog.Level) bool { return true }
func (h *ctxRecorder) Handle(ctx context.Context, _ slog.Record) error {
	*h.seen = ctx
	return nil
}
func (h *ctxRecorder) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *ctxRecorder) WithGroup(string) slog.Handler      { return h }

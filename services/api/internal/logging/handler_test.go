package logging

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"
)

// ref: monitoring.FAIL_OPEN.1 — errWriter simulates a broken sink for fail-open tests
// errWriter is an io.Writer that always returns an error.
type errWriter struct{ err error }

func (w *errWriter) Write(p []byte) (int, error) { return 0, w.err }

// ref: monitoring.OBSERVABILITY.1 — parse a single meta_warning JSON record
func decodeFirstLine(t *testing.T, buf *bytes.Buffer) map[string]any {
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

// ref: monitoring.FAIL_OPEN.1, monitoring.FAIL_OPEN.2 — Handle returns nil
// even when the primary writer fails, and the caller (slog default logger)
// never sees the error. slog.Log discards Handle errors at the call site, so
// we assert here at the Handle level directly.
func TestFailOpenHandler_PrimaryFailureReturnsNil(t *testing.T) {
	primary := &errWriter{err: errors.New("stdout closed")}
	meta := &bytes.Buffer{}
	h := newFailOpen(primary, meta, slog.LevelInfo)

	err := h.Handle(context.Background(), slog.NewRecord(time.Now(), slog.LevelInfo, "test", 0))
	if err != nil {
		t.Errorf("expected nil error from fail-open handler, got %v", err)
	}
}

// ref: monitoring.OBSERVABILITY.1 — when primary fails, a meta_warning event
// is written to the meta sink.
func TestFailOpenHandler_EmitsMetaWarningOnPrimaryFailure(t *testing.T) {
	primary := &errWriter{err: errors.New("stdout closed")}
	meta := &bytes.Buffer{}
	h := newFailOpen(primary, meta, slog.LevelInfo)

	_ = h.Handle(context.Background(), slog.NewRecord(time.Now(), slog.LevelInfo, "test", 0))

	rec := decodeFirstLine(t, meta)
	if rec["event"] != "meta_warning" {
		t.Errorf("expected event=meta_warning, got %v", rec["event"])
	}
	if rec["level"] != "WARN" {
		t.Errorf("expected level=WARN, got %v", rec["level"])
	}
	if rec["cause"] != "stdout closed" {
		t.Errorf("expected cause=stdout closed, got %v", rec["cause"])
	}
}

// ref: monitoring.FAIL_OPEN.1 — when primary succeeds, nothing is written to meta.
func TestFailOpenHandler_NoMetaOnPrimarySuccess(t *testing.T) {
	primary := &bytes.Buffer{}
	meta := &bytes.Buffer{}
	h := newFailOpen(primary, meta, slog.LevelInfo)

	_ = h.Handle(context.Background(), slog.NewRecord(time.Now(), slog.LevelInfo, "test", 0))

	if meta.Len() != 0 {
		t.Errorf("expected no meta output on success, got %q", meta.String())
	}
	if primary.Len() == 0 {
		t.Error("expected primary write to produce output, got empty")
	}
}

// ref: monitoring.FAIL_OPEN.1 — meta warning is fail-open too: if the meta
// sink also fails, Handle still returns nil.
func TestFailOpenHandler_MetaFailureAlsoReturnsNil(t *testing.T) {
	primary := &errWriter{err: errors.New("primary broken")}
	meta := &errWriter{err: errors.New("meta broken")}
	h := newFailOpen(primary, meta, slog.LevelInfo)

	if err := h.Handle(context.Background(), slog.NewRecord(time.Now(), slog.LevelInfo, "test", 0)); err != nil {
		t.Errorf("expected nil error when both sinks fail, got %v", err)
	}
}

// ref: monitoring.OBSERVABILITY.2 — Heartbeat emits one event at start, then
// ticks every interval until the context is cancelled.
func TestHeartbeat_EmitsOnTick(t *testing.T) {
	buf := &syncBuf{}
	prev := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(buf, &slog.HandlerOptions{Level: slog.LevelInfo})))
	t.Cleanup(func() { slog.SetDefault(prev) })

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		Heartbeat(ctx, 20*time.Millisecond)
		close(done)
	}()

	// Wait for at least 3 ticks (initial + 2 ticks).
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if strings.Count(buf.String(), `"event":"heartbeat"`) >= 3 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}

	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("heartbeat did not stop on ctx cancel")
	}

	count := strings.Count(buf.String(), `"event":"heartbeat"`)
	if count < 3 {
		t.Errorf("expected at least 3 heartbeats, got %d (buf=%q)", count, buf.String())
	}
}

// ref: monitoring.OBSERVABILITY.2 — syncBuf collects concurrent heartbeat writes
// syncBuf is a thread-safe bytes.Buffer for slog handler output.
type syncBuf struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (s *syncBuf) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.Write(p)
}

func (s *syncBuf) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.String()
}

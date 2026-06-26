package importer

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// ref: importer.RATE.3 — first sync (ErrNoRows) must allow the call.
func TestStore_CanSync_FirstSyncAllows(t *testing.T) {
	s := &Store{
		canSyncRow: func(ctx context.Context, userID string) (int, time.Time, error) {
			return 0, time.Time{}, pgx.ErrNoRows
		},
	}
	ok, err := s.CanSync(context.Background(), "user-1", 3)
	if !ok || err != nil {
		t.Fatalf("expected (true, nil) on first sync, got (%v, %v)", ok, err)
	}
}

// ref: importer.RATE.3 — any real DB error must fail CLOSED, not allow the call.
func TestStore_CanSync_FailsClosedOnDBError(t *testing.T) {
	dbErr := errors.New("connection refused")
	s := &Store{
		canSyncRow: func(ctx context.Context, userID string) (int, time.Time, error) {
			return 0, time.Time{}, dbErr
		},
	}
	ok, err := s.CanSync(context.Background(), "user-1", 3)
	if ok {
		t.Fatal("expected ok=false on DB error (fail closed)")
	}
	if !errors.Is(err, dbErr) {
		t.Fatalf("expected DB error to propagate, got %v", err)
	}
}

// ref: importer.RATE.3 — within-window under-limit allows; at-or-over-limit denies.
func TestStore_CanSync_QuotaEnforced(t *testing.T) {
	// reset_at is a future timestamp — window is still open.
	future := truncateToDay(time.Now().UTC()).Add(24 * time.Hour)
	s := &Store{
		canSyncRow: func(ctx context.Context, userID string) (int, time.Time, error) {
			return 3, future, nil
		},
	}
	if ok, _ := s.CanSync(context.Background(), "user-1", 3); ok {
		t.Fatal("count==limit must deny")
	}
	if ok, _ := s.CanSync(context.Background(), "user-1", 4); !ok {
		t.Fatal("count<limit must allow")
	}
}

// ref: importer.BGG_SYNC.5 — expired window (reset_at in the past) resets the quota.
func TestStore_CanSync_ResetsAfterWindowExpires(t *testing.T) {
	// reset_at in the past → window has expired → fresh start allowed.
	past := time.Now().UTC().Add(-24 * time.Hour)
	s := &Store{
		canSyncRow: func(ctx context.Context, userID string) (int, time.Time, error) {
			return 99, past, nil
		},
	}
	if ok, err := s.CanSync(context.Background(), "user-1", 3); !ok || err != nil {
		t.Fatalf("expired window should allow, got (%v, %v)", ok, err)
	}
}

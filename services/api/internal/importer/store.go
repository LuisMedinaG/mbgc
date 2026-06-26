package importer

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
)

type Store struct {
	db *pgxpool.Pool
	// canSyncRow is overridable for unit tests. Defaults to the real DB query.
	canSyncRow func(ctx context.Context, userID string) (count int, resetAt time.Time, err error)
}

// ref: importer.RATE.4 — initialize store with default rate-limit loader
func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db, canSyncRow: defaultCanSyncRow(db)}
}

// ref: importer.RATE.5 — load rate-limit count/reset_at row for a user
func defaultCanSyncRow(db *pgxpool.Pool) func(ctx context.Context, userID string) (int, time.Time, error) {
	return func(ctx context.Context, userID string) (int, time.Time, error) {
		var count int
		var resetAt time.Time
		err := db.QueryRow(ctx,
			`SELECT count, reset_at FROM importer.rate_limits WHERE user_id = $1`,
			userID).Scan(&count, &resetAt)
		return count, resetAt, err
	}
}

// ref: importer.RATE.1 — checks rate_limits table keyed by user_id
// reset_at is the absolute UTC time when the current window expires.
// ref: importer.RATE.3 — distinguishes first-sync (ErrNoRows) from real DB failure;
//
//	on real failure, fails CLOSED to preserve the quota.
func (s *Store) CanSync(ctx context.Context, userID string, limit int) (bool, error) {
	count, resetAt, err := s.canSyncRow(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	if time.Now().UTC().After(resetAt) {
		return true, nil // window expired — start a fresh window
	}
	return count < limit, nil
}

func (s *Store) RecordSync(ctx context.Context, userID string, tier string) error {
	resetAt := windowEnd(effectiveTierForWindow(tier), time.Now())
	_, err := s.db.Exec(ctx,
		`INSERT INTO importer.rate_limits (user_id, count, reset_at)
		 VALUES ($1, 1, $2)
		 ON CONFLICT (user_id) DO UPDATE
		   SET count = CASE
		     WHEN now() AT TIME ZONE 'UTC' > importer.rate_limits.reset_at THEN 1
		     ELSE importer.rate_limits.count + 1
		   END,
		   reset_at = CASE
		     WHEN now() AT TIME ZONE 'UTC' > importer.rate_limits.reset_at THEN $2
		     ELSE importer.rate_limits.reset_at
		   END`,
		userID, resetAt)
	return err
}

// ref: importer.BGG_SYNC.6 — each sync recorded with user, game counts, and timestamp
func (s *Store) LogSync(ctx context.Context, userID string, imported int, fullRefresh bool) error {
	_, err := s.db.Exec(ctx,
		`INSERT INTO importer.sync_log (user_id, games_imported, full_refresh)
		 VALUES ($1, $2, $3)`, userID, imported, fullRefresh)
	return err
}

// ref: importer.RATE.2 — admin users have a hard daily cap; pro users ≈ hourly; basic weekly
func (s *Store) CheckRateLimit(ctx context.Context, userID string, isAdmin bool, tier string, limits SyncLimits) error {
	limit := limits.Basic
	if isAdmin {
		limit = limits.Admin
	} else if tier == "pro" {
		limit = limits.Pro
	}
	ok, err := s.CanSync(ctx, userID, limit)
	if err != nil {
		return err
	}
	if !ok {
		return apierr.ErrRateLimit
	}
	return nil
}

// windowEnd returns when the rate-limit window expires for the given effective tier.
// basic → weekly (next Monday midnight UTC)
// pro / admin → daily (tomorrow midnight UTC)
func windowEnd(tier string, now time.Time) time.Time {
	switch tier {
	case "pro", "admin":
		return truncateToDay(now.UTC()).Add(24 * time.Hour)
	default: // "basic"
		return truncateToWeek(now.UTC()).Add(7 * 24 * time.Hour)
	}
}

// effectiveTierForWindow maps the tier stored in the DB to the window tier.
// Admins use a daily window (same as pro) since their limit is already high.
func effectiveTierForWindow(tier string) string {
	if tier == "pro" {
		return "pro"
	}
	return tier
}

func truncateToDay(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
}

// truncateToWeek returns Monday 00:00:00 UTC of the week containing t.
func truncateToWeek(t time.Time) time.Time {
	t = t.UTC()
	weekday := int(t.Weekday())
	if weekday == 0 {
		weekday = 7 // Sunday = 7 in ISO 8601
	}
	daysToMonday := weekday - 1
	y, m, d := t.Date()
	return time.Date(y, m, d-daysToMonday, 0, 0, 0, 0, time.UTC)
}

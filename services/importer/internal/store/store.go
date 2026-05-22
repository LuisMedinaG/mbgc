package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/services/importer/internal/model"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

type Store struct {
	db *pgxpool.Pool
}

func New(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

// CanSync reports whether the user is under their daily sync quota.
func (s *Store) CanSync(ctx context.Context, userID string, limit int) (bool, error) {
	var count int
	var resetDate time.Time
	err := s.db.QueryRow(ctx,
		`SELECT count, reset_date FROM importer.rate_limits WHERE user_id = $1`,
		userID).Scan(&count, &resetDate)
	if err != nil {
		// No row — first sync ever, always allowed
		return true, nil
	}
	// Reset if a new day
	if resetDate.Before(truncateToDay(time.Now())) {
		return true, nil
	}
	return count < limit, nil
}

// RecordSync increments the sync counter for today.
func (s *Store) RecordSync(ctx context.Context, userID string) error {
	_, err := s.db.Exec(ctx,
		`INSERT INTO importer.rate_limits (user_id, count, reset_date)
		 VALUES ($1, 1, current_date)
		 ON CONFLICT (user_id) DO UPDATE
		   SET count = CASE
		     WHEN importer.rate_limits.reset_date < current_date THEN 1
		     ELSE importer.rate_limits.count + 1
		   END,
		   reset_date = current_date`,
		userID)
	return err
}

// LogSync records a completed sync in the audit log.
func (s *Store) LogSync(ctx context.Context, userID string, imported int, fullRefresh bool) error {
	_, err := s.db.Exec(ctx,
		`INSERT INTO importer.sync_log (user_id, games_imported, full_refresh)
		 VALUES ($1, $2, $3)`, userID, imported, fullRefresh)
	return err
}

func truncateToDay(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
}

// CheckRateLimit returns ErrRateLimit if the user has exceeded their quota.
func (s *Store) CheckRateLimit(ctx context.Context, userID string, isAdmin bool, limitUser, limitAdmin int) error {
	limit := limitUser
	if isAdmin {
		limit = limitAdmin
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

// GetBGGUsername retrieves the BGG username for a user via the profile service.
// Note: importer calls auth-service for this — stored here for reference.
var _ = (*model.RateLimit)(nil) // ensure model is used

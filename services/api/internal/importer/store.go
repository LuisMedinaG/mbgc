package importer

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

type Store struct {
	db *pgxpool.Pool
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) CanSync(ctx context.Context, userID string, limit int) (bool, error) {
	var count int
	var resetDate time.Time
	err := s.db.QueryRow(ctx,
		`SELECT count, reset_date FROM importer.rate_limits WHERE user_id = $1`,
		userID).Scan(&count, &resetDate)
	if err != nil {
		return true, nil
	}
	if resetDate.Before(truncateToDay(time.Now())) {
		return true, nil
	}
	return count < limit, nil
}

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

func (s *Store) LogSync(ctx context.Context, userID string, imported int, fullRefresh bool) error {
	_, err := s.db.Exec(ctx,
		`INSERT INTO importer.sync_log (user_id, games_imported, full_refresh)
		 VALUES ($1, $2, $3)`, userID, imported, fullRefresh)
	return err
}

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

func truncateToDay(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
}

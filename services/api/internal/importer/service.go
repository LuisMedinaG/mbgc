package importer

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type importerStore interface {
	CheckRateLimit(ctx context.Context, userID string, isAdmin bool, limitUser, limitAdmin int) error
	RecordSync(ctx context.Context, userID string) error
	LogSync(ctx context.Context, userID string, imported int, fullRefresh bool) error
}

type bggClient interface {
	Available() bool
}

type gameService interface {
	GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error)
	CreateGame(ctx context.Context, userID string, bggID int) (int64, error)
}

type Service struct {
	store   importerStore
	bgg     bggClient
	gameSvc gameService
}

func NewService(st importerStore, bggClient bggClient, gameSvc gameService) *Service {
	return &Service{store: st, bgg: bggClient, gameSvc: gameSvc}
}

// syncKind is the value of the sync_kind attribute on a sync_* event.
// Values are intentionally coarse: incremental vs full_refresh.
const (
	syncKindIncremental = "incremental"
	syncKindFullRefresh = "full_refresh"
)

// ref: importer.BGG_SYNC.2 — sync is disabled when BGG credentials are not configured
// ref: monitoring.SINK.5 — emits sync_start, sync_ok, or sync_error across the lifetime of a sync
func (s *Service) Sync(r *http.Request, userID, bggUsername string, isAdmin bool, fullRefresh bool, limitUser, limitAdmin int) (*SyncResult, error) {
	ctx := r.Context()
	kind := syncKindIncremental
	if fullRefresh {
		kind = syncKindFullRefresh
	}

	if !s.bgg.Available() {
		// ref: monitoring.SINK.5 — sync_error at error level for configuration failure
		httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
		return nil, fmt.Errorf("BGG sync is not configured (no BGG_TOKEN or BGG_COOKIE)")
	}
	if err := s.store.CheckRateLimit(ctx, userID, isAdmin, limitUser, limitAdmin); err != nil {
		// ref: monitoring.SINK.5 — sync_error at warn level for rate-limit (per-handoff, not a server fault)
		level := slog.LevelWarn
		if !errors.Is(err, apierr.ErrRateLimit) {
			level = slog.LevelError
		}
		httpx.Record(r, "sync_error", level, "sync_kind", kind)
		return nil, err
	}

	// ref: monitoring.SINK.5 — sync_start fires once the early-rejection checks have passed
	httpx.Record(r, "sync_start", slog.LevelInfo, "sync_kind", kind)

	// TODO: fetch BGG collection, create games via gameSvc
	result := &SyncResult{}
	if err := s.store.RecordSync(ctx, userID); err != nil {
		// ref: monitoring.SINK.5 — sync_error at error level for store-layer failure
		httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
		return nil, err
	}
	if err := s.store.LogSync(ctx, userID, result.Imported, fullRefresh); err != nil {
		// ref: monitoring.SINK.5 — sync_error at error level for store-layer failure
		httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
		return nil, err
	}
	// ref: monitoring.SINK.5 — sync_ok with imported game count
	httpx.Record(r, "sync_ok", slog.LevelInfo, "sync_kind", kind, "game_count", result.Imported)
	return result, nil
}

func (s *Service) ParseCSVPreview(r io.Reader) ([]CSVPreviewRow, error) {
	reader := csv.NewReader(r)
	headers, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("empty or invalid CSV")
	}

	bggIDCol := -1
	nameCol := -1
	for i, h := range headers {
		switch strings.ToLower(strings.TrimSpace(h)) {
		case "objectid", "bgg_id", "bggid":
			bggIDCol = i
		case "objectname", "name":
			nameCol = i
		}
	}
	if bggIDCol == -1 {
		return nil, fmt.Errorf("CSV must have an 'objectid' column")
	}

	var rows []CSVPreviewRow
	for len(rows) < 100 {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}
		if bggIDCol >= len(record) {
			continue
		}
		id, err := strconv.Atoi(strings.TrimSpace(record[bggIDCol]))
		if err != nil {
			continue
		}
		row := CSVPreviewRow{BGGID: id}
		if nameCol >= 0 && nameCol < len(record) {
			row.Name = strings.TrimSpace(record[nameCol])
		}
		rows = append(rows, row)
	}
	return rows, nil
}

// ref: importer.GAME_CREATION.2 — importing the same BGG game twice does not create a duplicate
// ref: importer.CSV_IMPORT.4 — importing skips games already present in the collection
func (s *Service) ImportBGGIDs(ctx context.Context, userID string, bggIDs []int) (*SyncResult, error) {
	result := &SyncResult{}
	for _, id := range bggIDs {
		exists, err := s.gameSvc.GameExistsByBGGID(ctx, userID, id)
		if err != nil {
			result.Failed = append(result.Failed, strconv.Itoa(id))
			continue
		}
		if exists {
			result.Skipped++
			continue
		}
		if _, err := s.gameSvc.CreateGame(ctx, userID, id); err != nil {
			result.Failed = append(result.Failed, strconv.Itoa(id))
			continue
		}
		result.Imported++
	}
	return result, nil
}

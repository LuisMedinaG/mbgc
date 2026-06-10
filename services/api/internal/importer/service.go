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
	"github.com/LuisMedinaG/mbgc/services/api/internal/game"
)

type importerStore interface {
	CheckRateLimit(ctx context.Context, userID string, isAdmin bool, limitUser, limitAdmin int) error
	RecordSync(ctx context.Context, userID string) error
	LogSync(ctx context.Context, userID string, imported int, fullRefresh bool) error
}

type bggClient interface {
	Available() bool
	FetchCollection(ctx context.Context, bggUsername string) ([]int, error)
	FetchGames(ctx context.Context, bggIDs []int) ([]BGGGame, error)
}

type gameService interface {
	GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error)
	UpsertBGGGame(ctx context.Context, userID string, g game.BGGGameData) (int64, bool, error)
}

type profileService interface {
	GetBGGUsername(ctx context.Context, userID string) (string, error)
}

type Service struct {
	store   importerStore
	bgg     bggClient
	gameSvc gameService
	profSvc profileService
}

func NewService(st importerStore, bggClient bggClient, gameSvc gameService, profSvc profileService) *Service {
	return &Service{store: st, bgg: bggClient, gameSvc: gameSvc, profSvc: profSvc}
}

// syncKind is the value of the sync_kind attribute on a sync_* event.
// Values are intentionally coarse: incremental vs full_refresh.
const (
	syncKindIncremental = "incremental"
	syncKindFullRefresh = "full_refresh"
)

// ref: importer.BGG_SYNC.2 — sync is disabled when BGG credentials are not configured
// ref: monitoring.SINK.5 — emits sync_start, sync_ok, or sync_error across the lifetime of a sync
func (s *Service) Sync(r *http.Request, userID, _ string, isAdmin bool, fullRefresh bool, limitUser, limitAdmin int) (*SyncResult, error) {
	ctx := r.Context()
	kind := syncKindIncremental
	if fullRefresh {
		kind = syncKindFullRefresh
	}

	if !s.bgg.Available() {
		// ref: monitoring.SINK.5 — sync_error at error level for configuration failure
		httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
		return nil, fmt.Errorf("%w: BGG sync is not configured (no BGG_TOKEN or BGG_COOKIE)", apierr.ErrInternal)
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

	// Fetch the user's BGG username from their profile (set via PUT /profile/bgg-username).
	// The JWT subject / username is the local account, not the BGG handle.
	bggUsername, err := s.profSvc.GetBGGUsername(ctx, userID)
	if err != nil {
		httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
		return nil, fmt.Errorf("fetching BGG username: %w", err)
	}

	result := &SyncResult{}

	if bggUsername == "" {
		// ref: monitoring.SINK.5 — sync_ok with 0 imported when user has no BGG username configured
		httpx.Record(r, "sync_ok", slog.LevelInfo, "sync_kind", kind, "game_count", 0)
		if err := s.store.RecordSync(ctx, userID); err != nil {
			return nil, err
		}
		if err := s.store.LogSync(ctx, userID, 0, fullRefresh); err != nil {
			return nil, err
		}
		return result, nil
	}

	// Fetch the user's BGG collection (owned items only)
	bggIDs, err := s.bgg.FetchCollection(ctx, bggUsername)
	if err != nil {
		httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
		return nil, fmt.Errorf("fetching BGG collection: %w", err)
	}

	// Determine which IDs need metadata fetched
	var toFetch []int
	if fullRefresh {
		toFetch = bggIDs
	} else {
		for _, id := range bggIDs {
			exists, err := s.gameSvc.GameExistsByBGGID(ctx, userID, id)
			if err != nil {
				continue
			}
			if !exists {
				toFetch = append(toFetch, id)
			}
		}
	}

	// Fetch metadata in batches
	if len(toFetch) > 0 {
		games, err := s.bgg.FetchGames(ctx, toFetch)
		if err != nil {
			httpx.Record(r, "sync_error", slog.LevelError, "sync_kind", kind)
			return nil, fmt.Errorf("fetching game metadata: %w", err)
		}
		for _, g := range games {
			data := bggGameToGameData(g)
			_, created, err := s.gameSvc.UpsertBGGGame(ctx, userID, data)
			if err != nil {
				result.Failed = append(result.Failed, strconv.Itoa(g.BGGID))
				continue
			}
			if created {
				result.Imported++
			} else {
				result.Skipped++
			}
		}
	}

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

func bggGameToGameData(g BGGGame) game.BGGGameData {
	data := game.BGGGameData{
		BGGID:       g.BGGID,
		Name:        g.Name,
		Description: g.Description,
		Categories:  g.Categories,
		Mechanics:   g.Mechanics,
		Types:       g.Types,
	}
	if g.YearPublished > 0 {
		v := g.YearPublished
		data.YearPublished = &v
	}
	if g.Image != "" {
		v := g.Image
		data.Image = &v
	}
	if g.Thumbnail != "" {
		v := g.Thumbnail
		data.Thumbnail = &v
	}
	if g.MinPlayers > 0 {
		v := g.MinPlayers
		data.MinPlayers = &v
	}
	if g.MaxPlayers > 0 {
		v := g.MaxPlayers
		data.MaxPlayers = &v
	}
	if g.PlayTime > 0 {
		v := g.PlayTime
		data.PlayTime = &v
	}
	if g.Weight > 0 {
		v := g.Weight
		data.Weight = &v
	}
	if g.Rating > 0 {
		v := g.Rating
		data.Rating = &v
	}
	if g.LanguageDependence > 0 {
		v := g.LanguageDependence
		data.LanguageDependence = &v
	}
	data.RecommendedPlayers = g.RecommendedPlayers
	return data
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

	// Fetch metadata for all IDs in one batch call (cheaper than per-ID)
	games, err := s.bgg.FetchGames(ctx, bggIDs)
	if err != nil {
		return nil, fmt.Errorf("fetching BGG metadata: %w", err)
	}
	gameByID := make(map[int]BGGGame, len(games))
	for _, g := range games {
		gameByID[g.BGGID] = g
	}

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
		g, ok := gameByID[id]
		if !ok {
			// BGG didn't return metadata — still create a stub so the user can
			// see the BGG ID and add details later.
			g = BGGGame{BGGID: id, Name: ""}
		}
		data := bggGameToGameData(g)
		if _, _, err := s.gameSvc.UpsertBGGGame(ctx, userID, data); err != nil {
			slog.Error("importer: upsert game", "bgg_id", id, "error", err)
			result.Failed = append(result.Failed, strconv.Itoa(id))
			continue
		}
		result.Imported++
	}
	return result, nil
}

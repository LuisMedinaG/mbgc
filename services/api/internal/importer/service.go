package importer

import (
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"strconv"
	"strings"
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

// ref: importer.BGG_SYNC.3 — checks BGG availability before syncing
func (s *Service) Sync(ctx context.Context, userID, bggUsername string, isAdmin bool, fullRefresh bool, limitUser, limitAdmin int) (*SyncResult, error) {
	if !s.bgg.Available() {
		return nil, fmt.Errorf("BGG sync is not configured (no BGG_TOKEN or BGG_COOKIE)")
	}
	if err := s.store.CheckRateLimit(ctx, userID, isAdmin, limitUser, limitAdmin); err != nil {
		return nil, err
	}
	// TODO: fetch BGG collection, create games via gameSvc
	result := &SyncResult{}
	if err := s.store.RecordSync(ctx, userID); err != nil {
		return nil, err
	}
	if err := s.store.LogSync(ctx, userID, result.Imported, fullRefresh); err != nil {
		return nil, err
	}
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

// ref: importer.CSV_IMPORT.10 — creates games via game service with GameExistsByBGGID check
// ref: importer.CSV_IMPORT.8 — deduplicates by BGG ID before creating
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

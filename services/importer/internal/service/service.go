package service

import (
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/importer/internal/bgg"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/model"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/store"
)

// GameClient is the interface for calling game-service to create games.
// Implemented by the HTTP client in internal/game/client.go.
type GameClient interface {
	CreateGame(ctx context.Context, userID string, bggID int) error
	GameExists(ctx context.Context, userID string, bggID int) (bool, error)
}

type Service struct {
	store      *store.Store
	bgg        *bgg.Client
	gameClient GameClient
}

func New(st *store.Store, bggClient *bgg.Client, gc GameClient) *Service {
	return &Service{store: st, bgg: bggClient, gameClient: gc}
}

// Sync fetches the user's BGG collection and imports new games.
func (s *Service) Sync(ctx context.Context, userID, bggUsername string, isAdmin bool, fullRefresh bool, limitUser, limitAdmin int) (*model.SyncResult, error) {
	if !s.bgg.Available() {
		return nil, fmt.Errorf("BGG sync is not configured (no BGG_TOKEN or BGG_COOKIE)")
	}
	if err := s.store.CheckRateLimit(ctx, userID, isAdmin, limitUser, limitAdmin); err != nil {
		return nil, err
	}
	// TODO: fetch BGG collection, create games via gameClient
	result := &model.SyncResult{}
	if err := s.store.RecordSync(ctx, userID); err != nil {
		return nil, err
	}
	if err := s.store.LogSync(ctx, userID, result.Imported, fullRefresh); err != nil {
		return nil, err
	}
	return result, nil
}

// ParseCSVPreview reads up to 100 rows from a CSV file and returns BGG IDs.
func (s *Service) ParseCSVPreview(r io.Reader) ([]model.CSVPreviewRow, error) {
	reader := csv.NewReader(r)
	headers, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("empty or invalid CSV")
	}

	// Find the objectid column (case-insensitive)
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

	var rows []model.CSVPreviewRow
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
		row := model.CSVPreviewRow{BGGID: id}
		if nameCol >= 0 && nameCol < len(record) {
			row.Name = strings.TrimSpace(record[nameCol])
		}
		rows = append(rows, row)
	}
	return rows, nil
}

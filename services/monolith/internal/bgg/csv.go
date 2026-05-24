package bgg

import (
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"log/slog"
	"strconv"
	"strings"

)

// CSVRow is a single parsed row from a BGG collection CSV export. Only the
// fields the importer cares about are kept; everything else in the BGG export
// (rating, weight, comment, etc.) is intentionally discarded.
type CSVRow struct {
	BGGID int64
	Name  string
}

// CSVParseResult is the outcome of parsing a BGG collection CSV. Rows holds
// the rows we could read; SkippedRows is the count of data rows that were
// dropped because they had no usable BGG ID.
type CSVParseResult struct {
	Rows        []CSVRow
	SkippedRows int
}

// Required CSV columns. The BGG export includes ~50 columns; we only need the
// BGG game id. The name is recommended (used in the preview UI before we hit
// the BGG API) but not strictly required — if absent we fall back to the id.
const (
	csvColBGGID = "objectid"
	csvColName  = "objectname"
)

// ParseCollectionCSV parses a BGG collection CSV export. The format is the one
// produced by https://boardgamegeek.com/collection/user/<username> via the
// "Download" link, which has a header row followed by one row per game. The
// only column required for a successful import is "objectid"; "objectname" is
// recommended for the preview.
func ParseCollectionCSV(r io.Reader) (CSVParseResult, error) {
	reader := csv.NewReader(r)
	reader.FieldsPerRecord = -1 // BGG exports occasionally have ragged rows
	reader.LazyQuotes = true

	header, err := reader.Read()
	if err != nil {
		if err == io.EOF {
			return CSVParseResult{}, fmt.Errorf("csv is empty")
		}
		return CSVParseResult{}, fmt.Errorf("reading csv header: %w", err)
	}

	idIdx, nameIdx := -1, -1
	for i, col := range header {
		switch strings.ToLower(strings.TrimSpace(col)) {
		case csvColBGGID:
			idIdx = i
		case csvColName:
			nameIdx = i
		}
	}
	if idIdx == -1 {
		return CSVParseResult{}, fmt.Errorf("csv is missing the required %q column", csvColBGGID)
	}

	var result CSVParseResult
	seen := make(map[int64]bool)
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return result, fmt.Errorf("reading csv row: %w", err)
		}
		if idIdx >= len(record) {
			result.SkippedRows++
			continue
		}
		raw := strings.TrimSpace(record[idIdx])
		if raw == "" {
			result.SkippedRows++
			continue
		}
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || id <= 0 {
			result.SkippedRows++
			continue
		}
		if seen[id] {
			continue // de-dupe within the file itself
		}
		seen[id] = true

		name := ""
		if nameIdx >= 0 && nameIdx < len(record) {
			name = strings.TrimSpace(record[nameIdx])
		}
		result.Rows = append(result.Rows, CSVRow{BGGID: id, Name: name})
	}
	return result, nil
}

// ImportByBGGIDs fetches game metadata for the given BGG IDs from the BGG API
// and inserts new games into the user's collection. IDs already owned by the
// user are skipped. Returns the number of games added, skipped (already owned),
// and failed (could not be fetched from BGG).
//
// This mirrors ImportCollection but is driven by an explicit ID list instead
// of a BGG collection-API call, so it can back the CSV import path.
func (c *Client) ImportByBGGIDs(ctx context.Context, s GameStore, ids []int64, userID int64) (added, skipped, failed int, err error) {
	if len(ids) == 0 {
		return 0, 0, 0, nil
	}

	owned, err := s.OwnedBGGIDs(userID)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("loading owned IDs: %w", err)
	}

	var idsToFetch []int64
	for _, id := range ids {
		if owned[id] {
			skipped++
			continue
		}
		idsToFetch = append(idsToFetch, id)
	}

	if len(idsToFetch) == 0 {
		return 0, skipped, 0, nil
	}

	var firstThingErr error
	for _, batch := range chunkIDs(idsToFetch, bggThingBatchSize) {
		games, fetchErr := c.fetchThingsParsed(ctx, batch...)
		if fetchErr != nil {
			if firstThingErr == nil {
				firstThingErr = fetchErr
			}
			failed += len(batch)
			slog.Warn("bgg thing fetch failed (csv import)", "batch_size", len(batch), "error", fetchErr)
			continue
		}
		// Track which IDs in the batch we actually got back so the rest can
		// be counted as failures (BGG sometimes silently drops unknown IDs).
		got := make(map[int64]bool, len(games))
		for _, game := range games {
			got[game.BGGID] = true
			if _, createErr := s.CreateGame(game, userID); createErr != nil {
				slog.Warn("create game from csv failed", "bgg_id", game.BGGID, "error", createErr)
				failed++
				continue
			}
			added++
		}
		for _, id := range batch {
			if !got[id] {
				failed++
			}
		}
	}

	if added == 0 && failed == len(idsToFetch) && firstThingErr != nil {
		return 0, skipped, failed, fmt.Errorf("could not load game details from BGG for any of %d game(s); last error: %w", len(idsToFetch), firstThingErr)
	}

	return added, skipped, failed, nil
}

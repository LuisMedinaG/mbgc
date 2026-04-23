package csv

import (
	"encoding/csv"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// CSVGame holds the fields parsed from an imported CSV row.
type CSVGame struct {
	Title      string
	Year       int
	MinPlayers int
	MaxPlayers int
	BGGID      int
}

// ParseCSV reads a CSV from r and returns the parsed games.
// Expected header: title,year,min_players,max_players,bgg_id
// Additional columns are ignored. bgg_id and numeric fields are optional.
func ParseCSV(r io.Reader) ([]CSVGame, error) {
	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true

	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("read header: %w", err)
	}

	// Build column index map.
	colIndex := make(map[string]int, len(header))
	for i, col := range header {
		colIndex[strings.ToLower(strings.TrimSpace(col))] = i
	}

	titleIdx, ok := colIndex["title"]
	if !ok {
		return nil, fmt.Errorf("CSV missing required column: title")
	}

	var games []CSVGame
	lineNum := 1
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read line %d: %w", lineNum, err)
		}
		lineNum++

		if titleIdx >= len(record) {
			continue
		}

		g := CSVGame{Title: strings.TrimSpace(record[titleIdx])}

		if idx, ok := colIndex["year"]; ok && idx < len(record) {
			if n, err := strconv.Atoi(strings.TrimSpace(record[idx])); err == nil {
				g.Year = n
			}
		}
		if idx, ok := colIndex["min_players"]; ok && idx < len(record) {
			if n, err := strconv.Atoi(strings.TrimSpace(record[idx])); err == nil {
				g.MinPlayers = n
			}
		}
		if idx, ok := colIndex["max_players"]; ok && idx < len(record) {
			if n, err := strconv.Atoi(strings.TrimSpace(record[idx])); err == nil {
				g.MaxPlayers = n
			}
		}
		if idx, ok := colIndex["bgg_id"]; ok && idx < len(record) {
			if n, err := strconv.Atoi(strings.TrimSpace(record[idx])); err == nil {
				g.BGGID = n
			}
		}

		games = append(games, g)
	}
	return games, nil
}

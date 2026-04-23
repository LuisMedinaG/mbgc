package handlers

import (
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/luismedinag/myboardgamecollection/middleware"
)

// ---- BGG XML API types ----

type bggCollection struct {
	XMLName xml.Name  `xml:"items"`
	Items   []bggItem `xml:"item"`
}

type bggItem struct {
	ObjectID int64     `xml:"objectid,attr"`
	Name     bggName   `xml:"name"`
	YearPub  bggYear   `xml:"yearpublished"`
	Stats    bggStats  `xml:"stats"`
	Image    string    `xml:"image"`
	Thumbnail string   `xml:"thumbnail"`
}

type bggName struct {
	Value string `xml:",chardata"`
}

type bggYear struct {
	Value string `xml:",chardata"`
}

type bggStats struct {
	MinPlayers int       `xml:"minplayers,attr"`
	MaxPlayers int       `xml:"maxplayers,attr"`
	Rating     bggRating `xml:"rating"`
}

type bggRating struct {
	AverageWeight bggAttrValue `xml:"averageweight"`
}

type bggAttrValue struct {
	Value string `xml:"value,attr"`
}

// bggFetch fetches and parses a BGG collection, retrying on 202 responses.
func bggFetch(username string) (*bggCollection, error) {
	url := fmt.Sprintf(
		"https://boardgamegeek.com/xmlapi2/collection?username=%s&own=1&stats=1",
		username,
	)
	client := &http.Client{Timeout: 30 * time.Second}

	const maxRetries = 5
	for i := 0; i < maxRetries; i++ {
		resp, err := client.Get(url)
		if err != nil {
			return nil, fmt.Errorf("bgg request: %w", err)
		}

		if resp.StatusCode == http.StatusAccepted {
			resp.Body.Close()
			// BGG needs time to prepare the response — retry after a delay.
			time.Sleep(3 * time.Second)
			continue
		}
		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			return nil, fmt.Errorf("bgg returned status %d", resp.StatusCode)
		}

		var col bggCollection
		err = xml.NewDecoder(resp.Body).Decode(&col)
		resp.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("decode bgg xml: %w", err)
		}
		return &col, nil
	}
	return nil, fmt.Errorf("bgg not ready after %d retries", maxRetries)
}

type importBGGRequest struct {
	BGGUsername string `json:"bgg_username"`
}

// ImportBGG handles POST /api/import/bgg (auth required).
// It calls the BGG XML API v2, upserts games, and adds them to the
// authenticated user's collection.
func ImportBGG(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		var req importBGGRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.BGGUsername == "" {
			jsonError(w, "bgg_username required", http.StatusBadRequest)
			return
		}

		col, err := bggFetch(req.BGGUsername)
		if err != nil {
			jsonError(w, "failed to fetch BGG collection: "+err.Error(), http.StatusBadGateway)
			return
		}

		imported := 0
		for _, item := range col.Items {
			title := strings.TrimSpace(item.Name.Value)
			if title == "" {
				continue
			}

			var yearPub *int
			if y, err := strconv.Atoi(strings.TrimSpace(item.YearPub.Value)); err == nil {
				yearPub = &y
			}

			var weight *float64
			if wv, err := strconv.ParseFloat(item.Stats.Rating.AverageWeight.Value, 64); err == nil && wv > 0 {
				weight = &wv
			}

			imageURL := strings.TrimSpace(item.Image)
			if imageURL == "" {
				imageURL = strings.TrimSpace(item.Thumbnail)
			}

			bggID := item.ObjectID
			minP := item.Stats.MinPlayers
			maxP := item.Stats.MaxPlayers

			// Upsert game by bgg_id.
			gameID := ""
			dbErr := db.QueryRowContext(r.Context(),
				`SELECT id FROM games WHERE bgg_id=?`, bggID,
			).Scan(&gameID)

			if dbErr == sql.ErrNoRows {
				gameID = newID()
				if _, dbErr = db.ExecContext(r.Context(),
					`INSERT INTO games (id, bgg_id, title, year_published, min_players, max_players, weight, image_url)
					 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
					gameID, bggID, title, yearPub, minP, maxP, weight, imageURL,
				); dbErr != nil {
					continue
				}
			} else if dbErr != nil {
				continue
			} else {
				_, _ = db.ExecContext(r.Context(),
					`UPDATE games SET title=?, year_published=?, min_players=?, max_players=?,
					        weight=?, image_url=?, updated_at=CURRENT_TIMESTAMP
					 WHERE id=?`,
					title, yearPub, minP, maxP, weight, imageURL, gameID,
				)
			}

			// Add to collection (ignore conflict — already owned).
			entryID := newID()
			_, _ = db.ExecContext(r.Context(),
				`INSERT OR IGNORE INTO collection_entries (id, user_id, game_id, status)
				 VALUES (?, ?, ?, 'owned')`,
				entryID, user.UserID, gameID,
			)
			imported++
		}

		jsonOK(w, map[string]int{"imported": imported}, http.StatusOK)
	}
}

// ImportCSV handles POST /api/import/csv (auth required).
// Accepts a multipart upload with field "file". The CSV must have a header row
// with at least a "title" column. Optional: year, min_players, max_players, bgg_id.
func ImportCSV(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		if err := r.ParseMultipartForm(10 << 20); err != nil {
			jsonError(w, "invalid multipart form", http.StatusBadRequest)
			return
		}

		file, _, err := r.FormFile("file")
		if err != nil {
			jsonError(w, "file field required", http.StatusBadRequest)
			return
		}
		defer file.Close()

		reader := csv.NewReader(file)
		header, err := reader.Read()
		if err != nil {
			jsonError(w, "cannot read CSV header", http.StatusBadRequest)
			return
		}

		// Build column index map.
		colIdx := map[string]int{}
		for i, h := range header {
			colIdx[strings.ToLower(strings.TrimSpace(h))] = i
		}
		titleIdx, ok := colIdx["title"]
		if !ok {
			jsonError(w, "CSV must contain a 'title' column", http.StatusBadRequest)
			return
		}

		col := func(row []string, name string) string {
			i, exists := colIdx[name]
			if !exists || i >= len(row) {
				return ""
			}
			return strings.TrimSpace(row[i])
		}

		imported := 0
		for {
			row, err := reader.Read()
			if err == io.EOF {
				break
			}
			if err != nil {
				continue
			}
			if titleIdx >= len(row) {
				continue
			}

			title := strings.TrimSpace(row[titleIdx])
			if title == "" {
				continue
			}

			var yearPub *int
			if s := col(row, "year"); s != "" {
				if y, err := strconv.Atoi(s); err == nil {
					yearPub = &y
				}
			}
			var minP *int
			if s := col(row, "min_players"); s != "" {
				if v, err := strconv.Atoi(s); err == nil {
					minP = &v
				}
			}
			var maxP *int
			if s := col(row, "max_players"); s != "" {
				if v, err := strconv.Atoi(s); err == nil {
					maxP = &v
				}
			}
			var bggIDPtr *int64
			if s := col(row, "bgg_id"); s != "" {
				if v, err := strconv.ParseInt(s, 10, 64); err == nil {
					bggIDPtr = &v
				}
			}

			// Upsert by bgg_id if present, otherwise insert new.
			gameID := ""
			if bggIDPtr != nil {
				_ = db.QueryRowContext(r.Context(),
					`SELECT id FROM games WHERE bgg_id=?`, *bggIDPtr,
				).Scan(&gameID)
			}

			if gameID == "" {
				gameID = newID()
				if _, err = db.ExecContext(r.Context(),
					`INSERT INTO games (id, bgg_id, title, year_published, min_players, max_players)
					 VALUES (?, ?, ?, ?, ?, ?)`,
					gameID, bggIDPtr, title, yearPub, minP, maxP,
				); err != nil {
					continue
				}
			} else {
				_, _ = db.ExecContext(r.Context(),
					`UPDATE games SET title=?, year_published=?, min_players=?, max_players=?,
					        updated_at=CURRENT_TIMESTAMP WHERE id=?`,
					title, yearPub, minP, maxP, gameID,
				)
			}

			entryID := newID()
			_, _ = db.ExecContext(r.Context(),
				`INSERT OR IGNORE INTO collection_entries (id, user_id, game_id, status)
				 VALUES (?, ?, ?, 'owned')`,
				entryID, user.UserID, gameID,
			)
			imported++
		}

		jsonOK(w, map[string]int{"imported": imported}, http.StatusOK)
	}
}

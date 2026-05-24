// Package importer handles BGG collection sync and CSV import endpoints.
package importer

import (
	"encoding/json"
	"encoding/csv"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/bgg"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

const (
	syncLimitRegular      = 3
	syncLimitAdmin        = 20
	maxCSVPreviewRows     = 100
	maxCSVUploadBytes     = 5 << 20 // 5 MB
)

// SyncStore is the subset of user store the import handler needs.
type SyncStore interface {
	CanSync(userID int64, limit int) (bool, error)
	RecordSync(userID int64) error
	GetBGGUsername(userID int64) (string, error)
}

// Handler serves import-related API routes.
type Handler struct {
	syncStore  SyncStore
	gameStore  bgg.GameStore // implemented by services/games.Store
	bggClient  *bgg.Client
}

// NewHandler creates a new import handler.
func NewHandler(syncStore SyncStore, gameStore bgg.GameStore, bggClient *bgg.Client) *Handler {
	return &Handler{syncStore: syncStore, gameStore: gameStore, bggClient: bggClient}
}

// Sync triggers a BGG collection sync for the authenticated user.
//
// POST /api/v1/import/sync
func (h *Handler) Sync(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		FullRefresh bool `json:"full_refresh"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	isAdmin := httpx.IsAdminFromContext(r.Context())
	limit := syncLimitRegular
	if isAdmin {
		limit = syncLimitAdmin
	}

	canSync, err := h.syncStore.CanSync(userID, limit)
	if err != nil {
		slog.Error("import.Sync: CanSync", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if !canSync {
		writeError(w, http.StatusTooManyRequests, fmt.Sprintf("sync limit reached (%d per day)", limit))
		return
	}

	bggUsername, err := h.syncStore.GetBGGUsername(userID)
	if err != nil {
		slog.Error("import.Sync: GetBGGUsername", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if bggUsername == "" {
		writeError(w, http.StatusUnprocessableEntity, "BGG username not set")
		return
	}

	if h.bggClient == nil {
		writeError(w, http.StatusServiceUnavailable, "BGG import is not configured")
		return
	}

	added, updated, total, err := h.bggClient.ImportCollection(
		r.Context(), h.gameStore, bggUsername, userID, isAdmin && body.FullRefresh,
	)
	if err != nil {
		slog.Error("import.Sync: ImportCollection", "error", err)
		writeError(w, http.StatusBadGateway, "BGG import failed")
		return
	}

	if err := h.syncStore.RecordSync(userID); err != nil {
		slog.Error("import.Sync: RecordSync", "error", err)
	}

	writeData(w, http.StatusOK, map[string]any{
		"added":   added,
		"updated": updated,
		"total":   total,
	})
}

// CSVPreview parses an uploaded BGG collection CSV and returns a preview.
//
// POST /api/v1/import/csv/preview
func (h *Handler) CSVPreview(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	result, err := readCSV(w, r)
	if err != nil {
		return // readCSV already wrote the error
	}
	if len(result.Rows) == 0 {
		writeError(w, http.StatusUnprocessableEntity, "no valid games found in CSV")
		return
	}

	owned, err := h.gameStore.OwnedBGGIDs(userID)
	if err != nil {
		slog.Error("import.CSVPreview: OwnedBGGIDs", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	limit := maxCSVPreviewRows
	if len(result.Rows) < limit {
		limit = len(result.Rows)
	}

	rows := make([]map[string]any, limit)
	for i := 0; i < limit; i++ {
		row := result.Rows[i]
		rows[i] = map[string]any{
			"bgg_id":        row.BGGID,
			"name":          row.Name,
			"already_owned": owned[row.BGGID],
		}
	}

	writeData(w, http.StatusOK, map[string]any{
		"rows":          rows,
		"total_rows":    len(result.Rows),
		"preview_limit": maxCSVPreviewRows,
	})
}

// CSVImport imports games by their BGG IDs.
//
// POST /api/v1/import/csv
func (h *Handler) CSVImport(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		BGGIDs []int64 `json:"bgg_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(body.BGGIDs) == 0 {
		writeError(w, http.StatusBadRequest, "bgg_ids required")
		return
	}

	if h.bggClient == nil {
		writeError(w, http.StatusServiceUnavailable, "BGG import is not configured")
		return
	}

	added, _, failed, err := h.bggClient.ImportByBGGIDs(r.Context(), h.gameStore, body.BGGIDs, userID)
	if err != nil {
		slog.Error("import.CSVImport: ImportByBGGIDs", "error", err)
		writeError(w, http.StatusBadGateway, "BGG import failed")
		return
	}

	writeData(w, http.StatusOK, map[string]any{
		"imported": added,
		"failed":   failed,
	})
}

// ── CSV parsing ───────────────────────────────────────────────────────────────

type csvRow struct {
	BGGID int64
	Name  string
}

type csvResult struct {
	Rows        []csvRow
	SkippedRows int
}

func readCSV(w http.ResponseWriter, r *http.Request) (csvResult, error) {
	r.Body = http.MaxBytesReader(w, r.Body, maxCSVUploadBytes)
	if err := r.ParseMultipartForm(maxCSVUploadBytes); err != nil {
		var maxErr *http.MaxBytesError
		if fmt.Sprintf("%T", err) == "*http.MaxBytesError" || isMaxBytesErr(err) {
			_ = maxErr
			writeError(w, http.StatusRequestEntityTooLarge, "file too large (max 5 MB)")
		} else {
			writeError(w, http.StatusBadRequest, "invalid multipart form")
		}
		return csvResult{}, err
	}

	f, _, err := r.FormFile("csv_file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "no file uploaded (field: csv_file)")
		return csvResult{}, err
	}
	defer f.Close()

	result, err := parseCollectionCSV(f)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return csvResult{}, err
	}
	return result, nil
}

func isMaxBytesErr(err error) bool {
	return strings.Contains(err.Error(), "request body too large")
}

func parseCollectionCSV(r io.Reader) (csvResult, error) {
	reader := csv.NewReader(r)
	reader.FieldsPerRecord = -1
	reader.LazyQuotes = true

	header, err := reader.Read()
	if err == io.EOF {
		return csvResult{}, fmt.Errorf("csv is empty")
	}
	if err != nil {
		return csvResult{}, fmt.Errorf("reading csv header: %w", err)
	}

	idIdx, nameIdx := -1, -1
	for i, col := range header {
		switch strings.ToLower(strings.TrimSpace(col)) {
		case "objectid":
			idIdx = i
		case "objectname":
			nameIdx = i
		}
	}
	if idIdx == -1 {
		return csvResult{}, fmt.Errorf("csv is missing the required \"objectid\" column")
	}

	var result csvResult
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
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || id <= 0 || seen[id] {
			result.SkippedRows++
			continue
		}
		seen[id] = true
		name := ""
		if nameIdx >= 0 && nameIdx < len(record) {
			name = strings.TrimSpace(record[nameIdx])
		}
		result.Rows = append(result.Rows, csvRow{BGGID: id, Name: name})
	}
	return result, nil
}

// ── Request / response helpers ────────────────────────────────────────────────

func requireUserID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return 0, false
	}
	return id, true
}

func writeData(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": v})
}

func writeError(w http.ResponseWriter, status int, msg string) {
	httpx.WriteJSONError(w, status, msg)
}


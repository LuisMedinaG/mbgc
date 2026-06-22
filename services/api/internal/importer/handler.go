package importer

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	svc            *Service
	syncLimitUser  int
	syncLimitAdmin int
}

func NewHandler(svc *Service, limitUser, limitAdmin int) *Handler {
	return &Handler{svc: svc, syncLimitUser: limitUser, syncLimitAdmin: limitAdmin}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	// ref: importer.BGG_SYNC.1 — POST /api/v1/import/sync
	mux.Handle("POST /api/v1/import/sync", auth(http.HandlerFunc(h.Sync)))
	// ref: importer.CSV_IMPORT.2 — POST /api/v1/import/csv/preview
	mux.Handle("POST /api/v1/import/csv/preview", auth(http.HandlerFunc(h.CSVPreview)))
	// ref: importer.CSV_IMPORT.7 — POST /api/v1/import/csv
	mux.Handle("POST /api/v1/import/csv", auth(http.HandlerFunc(h.CSVImport)))
}

// ref: importer.BGG_SYNC.8 — admins can trigger a full refresh
// ref: importer.BGG_SYNC.3 — rate-limited per user
// ref: importer.BGG_SYNC.7 — response includes imported, skipped, failed counts
func (h *Handler) Sync(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	isAdmin := httpx.IsAdminFromContext(r.Context())
	fullRefresh := r.URL.Query().Get("full_refresh") == "true" && isAdmin

	bggUsername := httpx.UsernameFromContext(r.Context())

	result, err := h.svc.Sync(r, userID, bggUsername, isAdmin, fullRefresh, h.syncLimitUser, h.syncLimitAdmin)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.New(result))
}

// ref: importer.CSV_IMPORT.1 — CSV file uploaded for preview before import is confirmed
// ref: importer.CSV_IMPORT.2 — preview shows game names and marks already-owned games
func (h *Handler) CSVPreview(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	file, _, err := r.FormFile("csv_file")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	defer file.Close()

	rows, err := h.svc.ParseCSVPreview(file)
	if err != nil {
		// ref: api-layer.ERR.1 — route dynamic errors through WriteError so the central
		// sentinel mapping is the only place a message becomes an HTTP response.
		httpx.WriteError(w, fmt.Errorf("%w: %s", apierr.ErrBadRequest, err.Error()))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.NewList(rows, 1, len(rows), len(rows)))
}

// ref: importer.CSV_IMPORT.3 — user selects which games to import from the preview list
// ref: importer.CSV_IMPORT.4 — importing skips games already in the collection
// ref: importer.CSV_IMPORT.5 — response includes counts of imported, skipped, and failed games
// ref: importer.CSV_IMPORT.6 — cap batch to match preview (100) — prevents 1MB body of ints
// triggering thousands of DB round-trips in a single request (amplification DoS).
const maxImportBatch = 100

func (h *Handler) CSVImport(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	var body struct {
		BGGIDs []int `json:"bgg_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil ||
		len(body.BGGIDs) == 0 || len(body.BGGIDs) > maxImportBatch {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	result, err := h.svc.ImportBGGIDs(r.Context(), userID, body.BGGIDs)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.New(result))
}

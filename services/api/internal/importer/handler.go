package importer

import (
	"encoding/json"
	"net/http"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
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

// ref: importer.BGG_SYNC.9 — admin-only full refresh mode
// ref: importer.BGG_SYNC.4 — rate-limited syncs per user
// ref: importer.BGG_SYNC.8 — returns SyncResult with counts
func (h *Handler) Sync(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	isAdmin := httpx.IsAdminFromContext(r.Context())
	fullRefresh := r.URL.Query().Get("full_refresh") == "true" && isAdmin

	bggUsername := httpx.UsernameFromContext(r.Context())

	result, err := h.svc.Sync(r.Context(), userID, bggUsername, isAdmin, fullRefresh, h.syncLimitUser, h.syncLimitAdmin)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.New(result))
}

// ref: importer.CSV_IMPORT.2 — multipart form upload
// ref: importer.CSV_IMPORT.3 — auto-detects BGG ID column header
// ref: importer.CSV_IMPORT.4 — returns up to 100 preview rows
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
		httpx.WriteJSON(w, http.StatusBadRequest,
			envelope.NewError(apierr.CodeBadRequest, err.Error()))
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.NewList(rows, 1, len(rows), len(rows)))
}

// ref: importer.CSV_IMPORT.7 — JSON body with bgg_ids array
// ref: importer.CSV_IMPORT.8 — deduplicates by BGG ID
// ref: importer.CSV_IMPORT.9 — returns import count results
func (h *Handler) CSVImport(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	var body struct {
		BGGIDs []int `json:"bgg_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body.BGGIDs) == 0 {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	result, err := h.svc.ImportBGGIDs(r.Context(), userID, body.BGGIDs)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.New(result))
}

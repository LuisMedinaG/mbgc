package handler

import (
	"encoding/json"
	"net/http"

	"github.com/LuisMedinaG/mbgc/services/importer/internal/config"
	"github.com/LuisMedinaG/mbgc/services/importer/internal/service"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	svc *service.Service
	cfg config.Config
}

func New(svc *service.Service, cfg config.Config) *Handler {
	return &Handler{svc: svc, cfg: cfg}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/import/sync", h.Sync)
	mux.HandleFunc("POST /api/v1/import/csv/preview", h.CSVPreview)
	mux.HandleFunc("POST /api/v1/import/csv", h.CSVImport)
}

// Sync godoc
//
//	@Summary     Sync BGG collection
//	@Tags        import
//	@Produce     json
//	@Param       full_refresh  query  bool  false  "Admin only: re-import all games"
//	@Success     200  {object}  envelope.Response[model.SyncResult]
//	@Failure     401  {object}  envelope.ErrorResponse
//	@Failure     429  {object}  envelope.ErrorResponse
//	@Router      /import/sync [post]
func (h *Handler) Sync(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	isAdmin := httpx.IsAdminFromContext(r.Context())
	fullRefresh := r.URL.Query().Get("full_refresh") == "true" && isAdmin

	// TODO: fetch bggUsername from auth-service or from request context
	bggUsername := r.Header.Get("X-BGG-Username") // populated by auth-service enrichment (future)

	result, err := h.svc.Sync(r.Context(), userID, bggUsername, isAdmin, fullRefresh, h.cfg.SyncLimitUser, h.cfg.SyncLimitAdmin)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.New(result))
}

// CSVPreview godoc
//
//	@Summary     Preview a BGG CSV export
//	@Tags        import
//	@Accept      multipart/form-data
//	@Produce     json
//	@Param       csv_file  formData  file  true  "BGG collection CSV export"
//	@Success     200  {object}  envelope.ListResponse[model.CSVPreviewRow]
//	@Failure     400  {object}  envelope.ErrorResponse
//	@Router      /import/csv/preview [post]
func (h *Handler) CSVPreview(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(10 << 20); err != nil { // 10 MB
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

// CSVImport godoc
//
//	@Summary     Import games from BGG IDs
//	@Tags        import
//	@Accept      json
//	@Produce     json
//	@Param       body  body  object{bgg_ids=[]int}  true  "BGG IDs to import"
//	@Success     200  {object}  envelope.Response[model.SyncResult]
//	@Failure     400  {object}  envelope.ErrorResponse
//	@Router      /import/csv [post]
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
	_ = userID
	// TODO: call game-service to create each game by BGG ID
	httpx.WriteJSON(w, http.StatusOK, envelope.New(map[string]any{
		"imported": 0,
		"message":  "not yet implemented",
	}))
}

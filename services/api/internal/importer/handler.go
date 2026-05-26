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
	mux.Handle("POST /api/v1/import/sync", auth(http.HandlerFunc(h.Sync)))
	mux.Handle("POST /api/v1/import/csv/preview", auth(http.HandlerFunc(h.CSVPreview)))
	mux.Handle("POST /api/v1/import/csv", auth(http.HandlerFunc(h.CSVImport)))
}

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

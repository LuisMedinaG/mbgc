package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/LuisMedinaG/mbgc/services/game/internal/model"
	"github.com/LuisMedinaG/mbgc/services/game/internal/service"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	svc *service.Service
}

func New(svc *service.Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	// Games
	mux.HandleFunc("GET /api/v1/games", h.ListGames)
	mux.HandleFunc("GET /api/v1/games/{id}", h.GetGame)
	mux.HandleFunc("DELETE /api/v1/games/{id}", h.DeleteGame)
	mux.HandleFunc("POST /api/v1/games/{id}/collections", h.SetGameCollections)
	mux.HandleFunc("POST /api/v1/games/bulk-collections", h.BulkCollections)
	mux.HandleFunc("PUT /api/v1/games/{id}/rules-url", h.UpdateRulesURL)
	mux.HandleFunc("POST /api/v1/games/{id}/player-aids", h.UploadPlayerAid)
	mux.HandleFunc("DELETE /api/v1/games/{id}/player-aids/{aid_id}", h.DeletePlayerAid)

	// Collections
	mux.HandleFunc("GET /api/v1/collections", h.ListCollections)
	mux.HandleFunc("POST /api/v1/collections", h.CreateCollection)
	mux.HandleFunc("PUT /api/v1/collections/{id}", h.UpdateCollection)
	mux.HandleFunc("DELETE /api/v1/collections/{id}", h.DeleteCollection)

	// Discover
	mux.HandleFunc("GET /api/v1/discover", h.Discover)
}

// requireUserID extracts the user ID from context, writing 401 and returning false if missing.
func requireUserID(w http.ResponseWriter, r *http.Request) (string, bool) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
	}
	return userID, ok
}

func (h *Handler) ListGames(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	f := model.GameFilter{
		Search:   r.URL.Query().Get("search"),
		Category: r.URL.Query().Get("category"),
		Page:     queryInt(r, "page", 1),
		Limit:    queryInt(r, "limit", 20),
	}
	games, total, err := h.svc.ListGames(r.Context(), userID, f)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.NewList(games, f.Page, f.Limit, total))
}

func (h *Handler) GetGame(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	game, err := h.svc.GetGame(r.Context(), id, userID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.New(game))
}

func (h *Handler) DeleteGame(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	if err := h.svc.DeleteGame(r.Context(), id, userID); err != nil {
		httpx.WriteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) SetGameCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	gameID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	var body struct {
		CollectionIDs []int64 `json:"collection_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	if err := h.svc.SetGameCollections(r.Context(), userID, gameID, body.CollectionIDs); err != nil {
		httpx.WriteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) BulkCollections(w http.ResponseWriter, r *http.Request) {
	// TODO: add multiple games to multiple collections at once
	httpx.WriteError(w, apierr.ErrBadRequest)
}

func (h *Handler) UpdateRulesURL(w http.ResponseWriter, r *http.Request) {
	// TODO: validate Google Drive URL, update DB
	httpx.WriteError(w, apierr.ErrBadRequest)
}

func (h *Handler) UploadPlayerAid(w http.ResponseWriter, r *http.Request) {
	// TODO: parse multipart, validate mime type, save to dataDir, insert DB record
	httpx.WriteError(w, apierr.ErrBadRequest)
}

func (h *Handler) DeletePlayerAid(w http.ResponseWriter, r *http.Request) {
	// TODO: delete DB record + file from disk
	httpx.WriteError(w, apierr.ErrBadRequest)
}

func (h *Handler) ListCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	cols, err := h.svc.ListCollections(r.Context(), userID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, envelope.NewList(cols, 1, len(cols), len(cols)))
}

func (h *Handler) CreateCollection(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	col, err := h.svc.CreateCollection(r.Context(), userID, body.Name, body.Description)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, envelope.New(col))
}

func (h *Handler) UpdateCollection(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	if err := h.svc.UpdateCollection(r.Context(), id, userID, body.Name, body.Description); err != nil {
		httpx.WriteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) DeleteCollection(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	if err := h.svc.DeleteCollection(r.Context(), id, userID); err != nil {
		httpx.WriteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Discover(w http.ResponseWriter, r *http.Request) {
	// TODO: filter games within a specific collection
	httpx.WriteError(w, apierr.ErrBadRequest)
}

func queryInt(r *http.Request, key string, fallback int) int {
	v := r.URL.Query().Get(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

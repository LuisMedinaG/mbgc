package game

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// ref: auth.MIDDLEWARE.6 — JWT auth middleware applied per-route, not globally
func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.Handle("GET /api/v1/games", auth(http.HandlerFunc(h.ListGames)))            // ref: collection.API.1
	mux.Handle("GET /api/v1/games/{id}", auth(http.HandlerFunc(h.GetGame)))          // ref: game-detail.DETAIL_VIEW.1
	mux.Handle("DELETE /api/v1/games/{id}", auth(http.HandlerFunc(h.DeleteGame)))    // ref: game-detail.DELETE.1
	mux.Handle("POST /api/v1/games/{id}/collections", auth(http.HandlerFunc(h.SetGameCollections))) // ref: vibes.ASSIGN.1
	mux.Handle("POST /api/v1/games/bulk-collections", auth(http.HandlerFunc(h.BulkCollections)))    // ref: vibes.BULK.1
	mux.Handle("PUT /api/v1/games/{id}/rules-url", auth(http.HandlerFunc(h.UpdateRulesURL)))        // ref: game-detail.RULES_URL.2
	mux.Handle("POST /api/v1/games/{id}/player-aids", auth(http.HandlerFunc(h.UploadPlayerAid)))    // ref: game-detail.PLAYER_AIDS.1
	mux.Handle("DELETE /api/v1/games/{id}/player-aids/{aid_id}", auth(http.HandlerFunc(h.DeletePlayerAid))) // ref: game-detail.PLAYER_AIDS.6
	mux.Handle("GET /api/v1/collections", auth(http.HandlerFunc(h.ListCollections)))    // ref: vibes.LIST.1
	mux.Handle("POST /api/v1/collections", auth(http.HandlerFunc(h.CreateCollection)))  // ref: vibes.CRUD.1
	mux.Handle("PUT /api/v1/collections/{id}", auth(http.HandlerFunc(h.UpdateCollection)))  // ref: vibes.CRUD.3
	mux.Handle("DELETE /api/v1/collections/{id}", auth(http.HandlerFunc(h.DeleteCollection))) // ref: vibes.CRUD.4
	mux.Handle("GET /api/v1/discover", auth(http.HandlerFunc(h.Discover)))              // ref: vibes.DISCOVER.1
}

// ref: auth.MULTI_TENANCY.2 — user identity extracted from context via httpx.UserIDFromContext
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
	f := GameFilter{
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

// ref: vibes.ASSIGN.2 — replaces entire collection assignment set for the game
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
	// TODO: parse multipart, validate mime type, save file, insert DB record
	httpx.WriteError(w, apierr.ErrBadRequest)
}

func (h *Handler) DeletePlayerAid(w http.ResponseWriter, r *http.Request) {
	// TODO: delete DB record + file
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

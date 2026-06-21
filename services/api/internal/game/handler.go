package game

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type gameStore interface {
	ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error)
	GetGame(ctx context.Context, id int64, userID string) (*Game, error)
	CreateGame(ctx context.Context, userID string, bggID int) (int64, error)
	GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error)
	UpsertBGGGame(ctx context.Context, userID string, g BGGGameData) (int64, bool, error)
	DeleteGame(ctx context.Context, id int64, userID string) error
	ListCollections(ctx context.Context, userID string) ([]Collection, error)
	CreateCollection(ctx context.Context, userID, name, description string) (*Collection, error)
	UpdateCollection(ctx context.Context, id int64, userID, name, description string) error
	DeleteCollection(ctx context.Context, id int64, userID string) error
	SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error
	UpdateRulesURL(ctx context.Context, gameID int64, userID, rulesURL string) error
	Discover(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error)
}

type Handler struct {
	svc gameStore
}

func NewHandler(svc gameStore) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.Handle("GET /api/v1/games", auth(http.HandlerFunc(h.ListGames)))                            // ref: collection.API.1
	mux.Handle("GET /api/v1/games/{id}", auth(http.HandlerFunc(h.GetGame)))                         // ref: game-detail.DETAIL_VIEW.1
	mux.Handle("DELETE /api/v1/games/{id}", auth(http.HandlerFunc(h.DeleteGame)))                   // ref: game-detail.DELETE.1
	mux.Handle("POST /api/v1/games/{id}/collections", auth(http.HandlerFunc(h.SetGameCollections))) // ref: vibes.ASSIGN.1
	mux.Handle("PUT /api/v1/games/{id}/rules-url", auth(http.HandlerFunc(h.UpdateRulesURL)))        // ref: game-detail.RULES_URL.1
	mux.Handle("GET /api/v1/collections", auth(http.HandlerFunc(h.ListCollections)))                // ref: vibes.LIST.1
	mux.Handle("POST /api/v1/collections", auth(http.HandlerFunc(h.CreateCollection)))              // ref: vibes.CRUD.1
	mux.Handle("PUT /api/v1/collections/{id}", auth(http.HandlerFunc(h.UpdateCollection)))          // ref: vibes.CRUD.3
	mux.Handle("DELETE /api/v1/collections/{id}", auth(http.HandlerFunc(h.DeleteCollection)))       // ref: vibes.CRUD.4
	mux.Handle("GET /api/v1/discover", auth(http.HandlerFunc(h.Discover)))                          // ref: vibes.DISCOVER.1
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
	// ref: collection.API.1 — clamp page/limit to safe bounds; attacker-controlled ?limit=1000000
	// would otherwise cause expensive full scans and unbounded memory in the response envelope.
	page := httpx.QueryInt(r, "page", 1)
	if page < 1 {
		page = 1
	}
	limit := httpx.QueryInt(r, "limit", 20)
	if limit < 1 || limit > 100 {
		limit = 20
	}
	f := GameFilter{
		Search:   httpx.Truncate(r.URL.Query().Get("search"), 255),
		Category: httpx.Truncate(r.URL.Query().Get("category"), 255),
		Page:     page,
		Limit:    limit,
	}
	games, total, err := h.svc.ListGames(r.Context(), userID, f)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.NewList(games, f.Page, f.Limit, total))
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
	httpx.WriteJSON(w, http.StatusOK, httpx.New(game))
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

// ref: game-detail.RULES_URL.1 — server-side allowlist runs in the store;
// we only parse + truncate here.
func (h *Handler) UpdateRulesURL(w http.ResponseWriter, r *http.Request) {
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
		RulesURL string `json:"rules_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	body.RulesURL = httpx.Truncate(body.RulesURL, 2048)
	if err := h.svc.UpdateRulesURL(r.Context(), gameID, userID, body.RulesURL); err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.New(map[string]any{
		"game_id":   gameID,
		"rules_url": body.RulesURL,
	}))
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
	httpx.WriteJSON(w, http.StatusOK, httpx.NewList(cols, 1, len(cols), len(cols)))
}

func (h *Handler) CreateCollection(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	// ref: api-layer.CONFIG.7 — cap user-supplied strings at 255 chars before persistence
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	body.Name = httpx.Truncate(body.Name, 255)
	body.Description = httpx.Truncate(body.Description, 255)
	col, err := h.svc.CreateCollection(r.Context(), userID, body.Name, body.Description)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, httpx.New(col))
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
	// ref: api-layer.CONFIG.7 — cap user-supplied strings at 255 chars before persistence
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	body.Name = httpx.Truncate(body.Name, 255)
	body.Description = httpx.Truncate(body.Description, 255)
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
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	collectionID, err := strconv.ParseInt(r.URL.Query().Get("collection_id"), 10, 64)
	if err != nil || collectionID == 0 {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	f := DiscoverFilter{
		CollectionID: collectionID,
		Type:         httpx.Truncate(r.URL.Query().Get("type"), 255),
		Category:     httpx.Truncate(r.URL.Query().Get("category"), 255),
		Mechanic:     httpx.Truncate(r.URL.Query().Get("mechanic"), 255),
	}
	games, total, col, err := h.svc.Discover(r.Context(), userID, f)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	type discoverResponse struct {
		Data       []Game      `json:"data"`
		Total      int         `json:"total"`
		Collection *Collection `json:"collection"`
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.New(discoverResponse{
		Data:       games,
		Total:      total,
		Collection: col,
	}))
}

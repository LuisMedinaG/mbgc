package catalog

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"path/filepath"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
	"github.com/LuisMedinaG/mbgc/services/api/internal/httpx"
	"github.com/google/uuid"
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
	CreatePlayerAid(ctx context.Context, userID string, gameID int64, filename string, label *string) (*PlayerAid, error)
	GetPlayerAid(ctx context.Context, userID string, gameID, aidID int64) (*PlayerAid, error)
	DeletePlayerAid(ctx context.Context, userID string, gameID, aidID int64) error
}

type storage interface {
	Upload(ctx context.Context, bucket, filename string, content io.Reader, contentType string) error
	Remove(ctx context.Context, bucket, filename string) error
}

type Handler struct {
	svc     gameStore
	storage storage
}

func NewHandler(svc gameStore, storage storage) *Handler {
	return &Handler{svc: svc, storage: storage}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.Handle("GET /api/v1/games", auth(http.HandlerFunc(h.ListGames)))                                   // ref: collection.API.1
	mux.Handle("GET /api/v1/games/{id}", auth(http.HandlerFunc(h.GetGame)))                                // ref: game-detail.DETAIL_VIEW.1
	mux.Handle("DELETE /api/v1/games/{id}", auth(http.HandlerFunc(h.DeleteGame)))                          // ref: game-detail.DELETE.1
	mux.Handle("POST /api/v1/games/{id}/collections", auth(http.HandlerFunc(h.SetGameCollections)))        // ref: vibes.ASSIGN.1
	mux.Handle("PUT /api/v1/games/{id}/rules-url", auth(http.HandlerFunc(h.UpdateRulesURL)))               // ref: game-detail.RULES_URL.1
	mux.Handle("POST /api/v1/games/{id}/player-aids", auth(http.HandlerFunc(h.CreatePlayerAid)))           // ref: player-aid.CREATE.1
	mux.Handle("DELETE /api/v1/games/{id}/player-aids/{aidID}", auth(http.HandlerFunc(h.DeletePlayerAid))) // ref: player-aid.DELETE.1
	mux.Handle("GET /api/v1/collections", auth(http.HandlerFunc(h.ListCollections)))                       // ref: vibes.LIST.1
	mux.Handle("POST /api/v1/collections", auth(http.HandlerFunc(h.CreateCollection)))                     // ref: vibes.CRUD.1
	mux.Handle("PUT /api/v1/collections/{id}", auth(http.HandlerFunc(h.UpdateCollection)))                 // ref: vibes.CRUD.3
	mux.Handle("DELETE /api/v1/collections/{id}", auth(http.HandlerFunc(h.DeleteCollection)))              // ref: vibes.CRUD.4
	mux.Handle("GET /api/v1/discover", auth(http.HandlerFunc(h.Discover)))                                 // ref: vibes.DISCOVER.1
}

func (h *Handler) ListGames(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	page, limit := httpx.Pagination(r, 20, 100)
	f := GameFilter{
		Search:   httpx.Truncate(r.URL.Query().Get("q"), 255),
		Category: httpx.Truncate(r.URL.Query().Get("category"), 255),
		Players:  httpx.Truncate(r.URL.Query().Get("players"), 16),
		Playtime: httpx.Truncate(r.URL.Query().Get("playtime"), 16),
		Weight:   httpx.Truncate(r.URL.Query().Get("weight"), 16),
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	id, err := httpx.PathInt64(r, "id")
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	id, err := httpx.PathInt64(r, "id")
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

type collectionRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

// ref: vibes.ASSIGN.2 — replaces entire collection assignment set for the game
func (h *Handler) SetGameCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	gameID, err := httpx.PathInt64(r, "id")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	var body struct {
		CollectionIDs []int64 `json:"collection_ids"`
	}
	if err := httpx.DecodeValidate(r.Body, &body); err != nil {
		httpx.WriteError(w, err)
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	gameID, err := httpx.PathInt64(r, "id")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	var body struct {
		RulesURL string `json:"rules_url"`
	}
	if err := httpx.DecodeValidate(r.Body, &body); err != nil {
		httpx.WriteError(w, err)
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
	userID, ok := httpx.RequireUserID(w, r)
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	var body collectionRequest
	if err := httpx.DecodeValidate(r.Body, &body); err != nil {
		httpx.WriteError(w, err)
		return
	}
	if body.Name == "" {
		httpx.WriteError(w, fmt.Errorf("%w: name is required", apierr.ErrBadRequest))
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	id, err := httpx.PathInt64(r, "id")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	var body collectionRequest
	if err := httpx.DecodeValidate(r.Body, &body); err != nil {
		httpx.WriteError(w, err)
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	id, err := httpx.PathInt64(r, "id")
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
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	collectionID, err := httpx.QueryInt64(r, "collection_id")
	if err != nil || collectionID == 0 {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	page, limit := httpx.Pagination(r, 20, 100)
	f := DiscoverFilter{
		CollectionID: collectionID,
		Category:     httpx.Truncate(r.URL.Query().Get("category"), 255),
		Mechanic:     httpx.Truncate(r.URL.Query().Get("mechanic"), 255),
		Page:         page,
		Limit:        limit,
	}
	games, total, col, err := h.svc.Discover(r.Context(), userID, f)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, struct {
		Collection *Collection    `json:"collection"`
		Data       []Game         `json:"data"`
		Meta       httpx.PageMeta `json:"meta"`
		Total      int            `json:"total"`
	}{
		Collection: col,
		Data:       games,
		Meta:       httpx.PageMeta{Page: page, Limit: limit, Total: total},
		Total:      total,
	})
}

type playerAidRequest struct {
	Filename string  `json:"filename"`
	Label    *string `json:"label,omitempty"`
}

func (h *Handler) CreatePlayerAid(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	gameID, err := httpx.PathInt64(r, "id")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}

	// ref: api-layer.SEC.6 — Player aids allow up to 5MB, overriding the global 1MB JSON limit.
	r.Body = http.MaxBytesReader(w, r.Body, 5<<20)
	if err := r.ParseMultipartForm(5 << 20); err != nil {
		httpx.WriteError(w, fmt.Errorf("%w: failed to parse form", apierr.ErrBadRequest))
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.WriteError(w, fmt.Errorf("%w: file is required", apierr.ErrBadRequest))
		return
	}
	defer file.Close()

	label := r.FormValue("label")
	var labelPtr *string
	if label != "" {
		l := httpx.Truncate(label, 255)
		labelPtr = &l
	}

	// Generate a unique filename to prevent collisions and overwrites in storage.
	ext := filepath.Ext(header.Filename)
	storageName := fmt.Sprintf("%s%s", uuid.NewString(), ext)

	if err := h.storage.Upload(r.Context(), "player-aids", storageName, file, header.Header.Get("Content-Type")); err != nil {
		httpx.WriteError(w, fmt.Errorf("failed to upload to storage: %w", err))
		return
	}

	aid, err := h.svc.CreatePlayerAid(r.Context(), userID, gameID, storageName, labelPtr)
	if err != nil {
		// Cleanup storage if database record creation fails.
		_ = h.storage.Remove(r.Context(), "player-aids", storageName)
		httpx.WriteError(w, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, httpx.New(aid))
}

func (h *Handler) DeletePlayerAid(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.RequireUserID(w, r)
	if !ok {
		return
	}
	gameID, err := httpx.PathInt64(r, "id")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	aidID, err := httpx.PathInt64(r, "aidID")
	if err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}

	// Fetch metadata first to get the filename for storage cleanup.
	aid, err := h.svc.GetPlayerAid(r.Context(), userID, gameID, aidID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}

	if err := h.svc.DeletePlayerAid(r.Context(), userID, gameID, aidID); err != nil {
		httpx.WriteError(w, err)
		return
	}

	// Delete from storage. Failure here is logged but doesn't block the response.
	if err := h.storage.Remove(r.Context(), "player-aids", aid.Filename); err != nil {
		slog.WarnContext(r.Context(), "failed to remove player aid from storage", "filename", aid.Filename, "error", err)
	}

	w.WriteHeader(http.StatusNoContent)
}

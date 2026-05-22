package collections

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/model"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/apierr"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

// GameFilter is implemented by the games store to filter games within a collection.
type GameFilter interface {
	FilterGamesByCollection(collectionID int64, typ, category, mechanic, players, playtime, weight, rating, lang, recPlayers string, userID int64) ([]model.Game, error)
}

// Handler serves collection-related and discover API routes.
type Handler struct {
	store  *Store
	games  GameFilter
}

// NewHandler creates a new collections handler.
func NewHandler(store *Store, games GameFilter) *Handler {
	return &Handler{store: store, games: games}
}

// ListCollections returns all collections owned by the authenticated user.
//
// GET /api/v1/collections
func (h *Handler) ListCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	colls, err := h.store.AllCollections(userID)
	if err != nil {
		slog.Error("collections.ListCollections", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeData(w, http.StatusOK, collectionsToAPI(colls))
}

// CreateCollection creates a new collection.
//
// POST /api/v1/collections
// Body: {"name": "...", "description": "..."}
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
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	name := strings.TrimSpace(body.Name)
	if name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if len(name) > 100 {
		writeError(w, http.StatusBadRequest, "name too long (max 100 characters)")
		return
	}

	id, err := h.store.CreateCollection(name, strings.TrimSpace(body.Description), userID)
	if err != nil {
		if errors.Is(err, apierr.ErrDuplicate) {
			writeError(w, http.StatusConflict, "collection already exists")
			return
		}
		slog.Error("collections.CreateCollection", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusCreated, map[string]any{
		"id": id, "name": name, "description": strings.TrimSpace(body.Description),
	})
}

// UpdateCollection renames / redescribes a collection.
//
// PUT /api/v1/collections/{id}
func (h *Handler) UpdateCollection(w http.ResponseWriter, r *http.Request) {
	id, ok := requireID(w, r)
	if !ok {
		return
	}
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	name := strings.TrimSpace(body.Name)
	if name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if len(name) > 100 {
		writeError(w, http.StatusBadRequest, "name too long (max 100 characters)")
		return
	}

	if _, err := h.store.GetCollection(id, userID); err != nil {
		writeError(w, http.StatusNotFound, "collection not found")
		return
	}

	if err := h.store.UpdateCollection(id, name, strings.TrimSpace(body.Description), userID); err != nil {
		if errors.Is(err, apierr.ErrDuplicate) {
			writeError(w, http.StatusConflict, "collection already exists")
			return
		}
		slog.Error("collections.UpdateCollection", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{
		"id": id, "name": name, "description": strings.TrimSpace(body.Description),
	})
}

// DeleteCollection removes a collection.
//
// DELETE /api/v1/collections/{id}
func (h *Handler) DeleteCollection(w http.ResponseWriter, r *http.Request) {
	id, ok := requireID(w, r)
	if !ok {
		return
	}
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	if err := h.store.DeleteCollection(id, userID); err != nil {
		slog.Error("collections.DeleteCollection", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Discover returns games in a collection with optional filters.
//
// GET /api/v1/discover?collection_id=X&...filters...
func (h *Handler) Discover(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	q := r.URL.Query()

	collectionIDStr := q.Get("collection_id")
	if collectionIDStr == "" {
		writeError(w, http.StatusBadRequest, "collection_id is required")
		return
	}
	collectionID, err := strconv.ParseInt(collectionIDStr, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid collection_id")
		return
	}

	collection, err := h.store.GetCollection(collectionID, userID)
	if err != nil {
		writeError(w, http.StatusNotFound, "collection not found")
		return
	}

	games, err := h.games.FilterGamesByCollection(
		collectionID,
		q.Get("type"), q.Get("category"), q.Get("mechanic"),
		q.Get("players"), q.Get("playtime"),
		q.Get("weight"), q.Get("rating"), q.Get("lang"), q.Get("rec_players"),
		userID,
	)
	if err != nil {
		slog.Error("collections.Discover: FilterGamesByCollection", "collectionID", collectionID, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"data":       gamesToAPI(games),
		"total":      len(games),
		"collection": collectionToAPI(collection),
	})
}

// ── JSON converters ───────────────────────────────────────────────────────────

func collectionToAPI(c model.Collection) map[string]any {
	return map[string]any{
		"id":          c.ID,
		"name":        c.Name,
		"description": c.Description,
		"created_at":  c.CreatedAt,
		"game_count":  c.GameCount,
	}
}

func collectionsToAPI(cs []model.Collection) []map[string]any {
	out := make([]map[string]any, 0, len(cs))
	for _, c := range cs {
		out = append(out, collectionToAPI(c))
	}
	return out
}

func gamesToAPI(gs []model.Game) []map[string]any {
	out := make([]map[string]any, len(gs))
	for i, g := range gs {
		out[i] = map[string]any{
			"id":                  g.ID,
			"bgg_id":              g.BGGID,
			"name":                g.Name,
			"description":         g.Description,
			"year_published":      g.YearPublished,
			"image":               g.Image,
			"thumbnail":           g.Thumbnail,
			"min_players":         g.MinPlayers,
			"max_players":         g.MaxPlayers,
			"play_time":           g.PlayTime,
			"categories":          g.Categories,
			"mechanics":           g.Mechanics,
			"types":               g.Types,
			"weight":              g.Weight,
			"rating":              g.Rating,
			"language_dependence": g.LanguageDependence,
			"recommended_players": g.RecommendedPlayers,
			"rules_url":           g.RulesURL,
		}
	}
	return out
}

// ── Request helpers ───────────────────────────────────────────────────────────

func requireID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

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

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	httpx.WriteJSONError(w, status, msg)
}

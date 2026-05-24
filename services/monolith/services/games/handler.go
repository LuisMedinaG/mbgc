package games

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/model"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/apierr"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

// Handler serves all games-related API routes.
type Handler struct{ store *Store }

// NewHandler creates a new games handler.
func NewHandler(store *Store) *Handler { return &Handler{store: store} }

// ListGames returns a paginated, filtered list of the user's games.
//
// GET /api/v1/games
func (h *Handler) ListGames(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	q := r.URL.Query()
	page, limit := parsePagination(r)
	games, total, err := h.store.FilterGames(
		q.Get("q"), q.Get("category"), q.Get("players"), q.Get("playtime"),
		q.Get("weight"), q.Get("rating"), q.Get("lang"), q.Get("rec_players"),
		page, limit, userID,
	)
	if err != nil {
		slog.Error("games.ListGames: FilterGames", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	categories, err := h.store.DistinctCategories(userID)
	if err != nil {
		slog.Error("games.ListGames: DistinctCategories", "error", err)
		categories = []string{}
	}

	h.populateCollections(games)

	writeJSON(w, http.StatusOK, map[string]any{
		"data":       gamesToAPI(games),
		"total":      total,
		"page":       page,
		"per_page":   limit,
		"categories": categories,
	})
}

// GetGame returns a single game with its collections and player aids.
//
// GET /api/v1/games/{id}
func (h *Handler) GetGame(w http.ResponseWriter, r *http.Request) {
	id, ok := requireID(w, r)
	if !ok {
		return
	}
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	game, err := h.store.GetGame(id, userID)
	if err != nil {
		writeError(w, http.StatusNotFound, "game not found")
		return
	}

	collections, err := h.store.CollectionsForGame(game.ID)
	if err != nil {
		slog.Error("games.GetGame: CollectionsForGame", "error", err)
	}

	aids, err := h.store.GetPlayerAids(game.ID)
	if err != nil {
		slog.Error("games.GetGame: GetPlayerAids", "error", err)
	}

	resp := gameToAPI(game)
	resp["vibes"] = collectionsToAPI(collections) // keep "vibes" key for frontend compat
	resp["player_aids"] = playerAidsToAPI(aids)

	writeData(w, http.StatusOK, resp)
}

// DeleteGame removes a game from the user's collection.
//
// DELETE /api/v1/games/{id}
func (h *Handler) DeleteGame(w http.ResponseWriter, r *http.Request) {
	id, ok := requireID(w, r)
	if !ok {
		return
	}
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	if _, err := h.store.GetGame(id, userID); err != nil {
		writeError(w, http.StatusNotFound, "game not found")
		return
	}
	if err := h.store.DeleteGame(id, userID); err != nil {
		slog.Error("games.DeleteGame", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// SetGameCollections replaces all collection associations for a game.
//
// POST /api/v1/games/{id}/collections
func (h *Handler) SetGameCollections(w http.ResponseWriter, r *http.Request) {
	id, ok := requireID(w, r)
	if !ok {
		return
	}
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		CollectionIDs []int64 `json:"collection_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if _, err := h.store.GetGame(id, userID); err != nil {
		writeError(w, http.StatusNotFound, "game not found")
		return
	}

	if err := h.store.SetGameCollections(userID, id, body.CollectionIDs); err != nil {
		if apierr.IsOwnership(err) {
			writeError(w, http.StatusNotFound, "one or more collections were not found")
			return
		}
		slog.Error("games.SetGameCollections", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{
		"game_id":        id,
		"collection_ids": body.CollectionIDs,
	})
}

// BulkCollections adds collections to multiple games at once.
//
// POST /api/v1/games/bulk-collections
func (h *Handler) BulkCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		GameIDs       []int64 `json:"game_ids"`
		CollectionIDs []int64 `json:"collection_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(body.GameIDs) == 0 || len(body.CollectionIDs) == 0 {
		writeError(w, http.StatusBadRequest, "game_ids and collection_ids required")
		return
	}

	if err := h.store.AddGamesToCollections(userID, body.GameIDs, body.CollectionIDs); err != nil {
		if apierr.IsOwnership(err) {
			writeError(w, http.StatusNotFound, "one or more games or collections were not found")
			return
		}
		slog.Error("games.BulkCollections", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{"updated": len(body.GameIDs)})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func (h *Handler) populateCollections(games []model.Game) {
	if len(games) == 0 {
		return
	}
	ids := make([]int64, len(games))
	for i, g := range games {
		ids[i] = g.ID
	}
	gameColls, err := h.store.CollectionsForGames(ids)
	if err != nil {
		slog.Error("games.populateCollections", "error", err)
		return
	}
	for i := range games {
		games[i].Collections = gameColls[games[i].ID]
	}
}

// ── JSON converters ───────────────────────────────────────────────────────────

func gameToAPI(g model.Game) map[string]any {
	return map[string]any{
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
		"vibes":               collectionsToAPI(g.Collections),
	}
}

func gamesToAPI(gs []model.Game) []map[string]any {
	out := make([]map[string]any, len(gs))
	for i, g := range gs {
		out[i] = gameToAPI(g)
	}
	return out
}

func collectionsToAPI(cs []model.Collection) []map[string]any {
	out := make([]map[string]any, 0, len(cs))
	for _, c := range cs {
		out = append(out, map[string]any{"id": c.ID, "name": c.Name})
	}
	return out
}

func playerAidToAPI(a model.PlayerAid) map[string]any {
	return map[string]any{
		"id": a.ID, "game_id": a.GameID, "filename": a.Filename, "label": a.Label,
	}
}

func playerAidsToAPI(as []model.PlayerAid) []map[string]any {
	out := make([]map[string]any, 0, len(as))
	for _, a := range as {
		out = append(out, playerAidToAPI(a))
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

func parsePagination(r *http.Request) (page, limit int) {
	page, _ = strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	limit, _ = strconv.Atoi(r.URL.Query().Get("limit"))
	if limit < 1 {
		limit = DefaultPageSize
	} else if limit > MaxPageSize {
		limit = MaxPageSize
	}
	return page, limit
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

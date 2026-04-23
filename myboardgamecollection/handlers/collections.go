package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/luismedinag/myboardgamecollection/middleware"
)

type CollectionEntry struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	GameID    string    `json:"game_id"`
	Status    string    `json:"status"`
	Rating    *int      `json:"rating,omitempty"`
	Notes     *string   `json:"notes,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Game      *Game     `json:"game,omitempty"`
}

type collectionListResponse struct {
	Total   int               `json:"total"`
	Page    int               `json:"page"`
	PerPage int               `json:"per_page"`
	Entries []CollectionEntry `json:"entries"`
}

// ListCollection handles GET /api/collections (auth required).
func ListCollection(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		var total int
		db.QueryRowContext(r.Context(),
			`SELECT COUNT(*) FROM collection_entries WHERE user_id=?`, user.UserID,
		).Scan(&total)

		rows, err := db.QueryContext(r.Context(),
			`SELECT ce.id, ce.user_id, ce.game_id, ce.status, ce.rating, ce.notes,
			        ce.created_at, ce.updated_at,
			        g.id, g.bgg_id, g.title, g.year_published, g.min_players, g.max_players,
			        g.weight, g.image_url, g.description, g.created_at, g.updated_at
			 FROM collection_entries ce
			 JOIN games g ON g.id = ce.game_id
			 WHERE ce.user_id=?
			 ORDER BY g.title`, user.UserID,
		)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		entries := make([]CollectionEntry, 0)
		for rows.Next() {
			var e CollectionEntry
			var g Game
			if err := rows.Scan(
				&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes,
				&e.CreatedAt, &e.UpdatedAt,
				&g.ID, &g.BGGID, &g.Title, &g.YearPublished, &g.MinPlayers, &g.MaxPlayers,
				&g.Weight, &g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
			); err != nil {
				jsonError(w, "internal error", http.StatusInternalServerError)
				return
			}
			e.Game = &g
			entries = append(entries, e)
		}
		if err := rows.Err(); err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, collectionListResponse{
			Total:   total,
			Page:    1,
			PerPage: total,
			Entries: entries,
		}, http.StatusOK)
	}
}

type addCollectionRequest struct {
	GameID string  `json:"game_id"`
	Status string  `json:"status"`
	Rating *int    `json:"rating"`
	Notes  *string `json:"notes"`
}

// AddToCollection handles POST /api/collections (auth required).
func AddToCollection(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		var req addCollectionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid request body", http.StatusBadRequest)
			return
		}
		if req.GameID == "" {
			jsonError(w, "game_id required", http.StatusBadRequest)
			return
		}
		if req.Status == "" {
			req.Status = "owned"
		}

		id := newID()
		_, err := db.ExecContext(r.Context(),
			`INSERT INTO collection_entries (id, user_id, game_id, status, rating, notes)
			 VALUES (?, ?, ?, ?, ?, ?)`,
			id, user.UserID, req.GameID, req.Status, req.Rating, req.Notes,
		)
		if err != nil {
			jsonError(w, "entry already exists or game not found", http.StatusConflict)
			return
		}

		var e CollectionEntry
		db.QueryRowContext(r.Context(),
			`SELECT id, user_id, game_id, status, rating, notes, created_at, updated_at
			 FROM collection_entries WHERE id=?`, id,
		).Scan(&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes, &e.CreatedAt, &e.UpdatedAt)

		jsonOK(w, e, http.StatusCreated)
	}
}

type updateCollectionRequest struct {
	Status string  `json:"status"`
	Rating *int    `json:"rating"`
	Notes  *string `json:"notes"`
}

// UpdateCollectionEntry handles PUT /api/collections/{id} (auth required).
func UpdateCollectionEntry(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		id := r.PathValue("id")
		var req updateCollectionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid request body", http.StatusBadRequest)
			return
		}

		result, err := db.ExecContext(r.Context(),
			`UPDATE collection_entries
			 SET status=?, rating=?, notes=?, updated_at=CURRENT_TIMESTAMP
			 WHERE id=? AND user_id=?`,
			req.Status, req.Rating, req.Notes, id, user.UserID,
		)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			jsonError(w, "entry not found", http.StatusNotFound)
			return
		}

		var e CollectionEntry
		db.QueryRowContext(r.Context(),
			`SELECT id, user_id, game_id, status, rating, notes, created_at, updated_at
			 FROM collection_entries WHERE id=?`, id,
		).Scan(&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes, &e.CreatedAt, &e.UpdatedAt)

		jsonOK(w, e, http.StatusOK)
	}
}

// RemoveFromCollection handles DELETE /api/collections/{id} (auth required).
func RemoveFromCollection(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		id := r.PathValue("id")
		result, err := db.ExecContext(r.Context(),
			`DELETE FROM collection_entries WHERE id=? AND user_id=?`, id, user.UserID,
		)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			jsonError(w, "entry not found", http.StatusNotFound)
			return
		}
		jsonOK(w, map[string]string{"status": "deleted"}, http.StatusOK)
	}
}

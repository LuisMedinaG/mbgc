package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"time"
)

type Game struct {
	ID            string    `json:"id"`
	BGGID         *int64    `json:"bgg_id,omitempty"`
	Title         string    `json:"title"`
	YearPublished *int      `json:"year_published,omitempty"`
	MinPlayers    *int      `json:"min_players,omitempty"`
	MaxPlayers    *int      `json:"max_players,omitempty"`
	Weight        *float64  `json:"weight,omitempty"`
	ImageURL      *string   `json:"image_url,omitempty"`
	Description   *string   `json:"description,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type gamesListResponse struct {
	Total   int    `json:"total"`
	Page    int    `json:"page"`
	PerPage int    `json:"per_page"`
	Games   []Game `json:"games"`
}

// ListGames handles GET /api/games.
func ListGames(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("q")
		page, _ := strconv.Atoi(r.URL.Query().Get("page"))
		perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
		if page < 1 {
			page = 1
		}
		if perPage < 1 || perPage > 100 {
			perPage = 20
		}
		offset := (page - 1) * perPage

		pattern := "%" + q + "%"

		var total int
		err := db.QueryRowContext(r.Context(),
			`SELECT COUNT(*) FROM games WHERE title LIKE ?`, pattern,
		).Scan(&total)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		rows, err := db.QueryContext(r.Context(),
			`SELECT id, bgg_id, title, year_published, min_players, max_players, weight,
			        image_url, description, created_at, updated_at
			 FROM games WHERE title LIKE ?
			 ORDER BY title LIMIT ? OFFSET ?`,
			pattern, perPage, offset,
		)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		games := make([]Game, 0)
		for rows.Next() {
			var g Game
			if err := rows.Scan(
				&g.ID, &g.BGGID, &g.Title, &g.YearPublished,
				&g.MinPlayers, &g.MaxPlayers, &g.Weight,
				&g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
			); err != nil {
				jsonError(w, "internal error", http.StatusInternalServerError)
				return
			}
			games = append(games, g)
		}
		if err := rows.Err(); err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, gamesListResponse{
			Total:   total,
			Page:    page,
			PerPage: perPage,
			Games:   games,
		}, http.StatusOK)
	}
}

// GetGame handles GET /api/games/{id}.
func GetGame(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		var g Game
		err := db.QueryRowContext(r.Context(),
			`SELECT id, bgg_id, title, year_published, min_players, max_players, weight,
			        image_url, description, created_at, updated_at
			 FROM games WHERE id = ?`, id,
		).Scan(
			&g.ID, &g.BGGID, &g.Title, &g.YearPublished,
			&g.MinPlayers, &g.MaxPlayers, &g.Weight,
			&g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			jsonError(w, "game not found", http.StatusNotFound)
			return
		}
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, g, http.StatusOK)
	}
}

type gameRequest struct {
	BGGID         *int64   `json:"bgg_id"`
	Title         string   `json:"title"`
	YearPublished *int     `json:"year_published"`
	MinPlayers    *int     `json:"min_players"`
	MaxPlayers    *int     `json:"max_players"`
	Weight        *float64 `json:"weight"`
	ImageURL      *string  `json:"image_url"`
	Description   *string  `json:"description"`
}

// CreateGame handles POST /api/games (admin).
func CreateGame(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req gameRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid request body", http.StatusBadRequest)
			return
		}
		if req.Title == "" {
			jsonError(w, "title required", http.StatusBadRequest)
			return
		}

		id := newID()
		_, err := db.ExecContext(r.Context(),
			`INSERT INTO games (id, bgg_id, title, year_published, min_players, max_players, weight, image_url, description)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			id, req.BGGID, req.Title, req.YearPublished, req.MinPlayers, req.MaxPlayers,
			req.Weight, req.ImageURL, req.Description,
		)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		var g Game
		db.QueryRowContext(r.Context(),
			`SELECT id, bgg_id, title, year_published, min_players, max_players, weight,
			        image_url, description, created_at, updated_at
			 FROM games WHERE id = ?`, id,
		).Scan(
			&g.ID, &g.BGGID, &g.Title, &g.YearPublished,
			&g.MinPlayers, &g.MaxPlayers, &g.Weight,
			&g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
		)
		jsonOK(w, g, http.StatusCreated)
	}
}

// UpdateGame handles PUT /api/games/{id} (admin).
func UpdateGame(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		var req gameRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid request body", http.StatusBadRequest)
			return
		}
		if req.Title == "" {
			jsonError(w, "title required", http.StatusBadRequest)
			return
		}

		result, err := db.ExecContext(r.Context(),
			`UPDATE games SET bgg_id=?, title=?, year_published=?, min_players=?, max_players=?,
			        weight=?, image_url=?, description=?, updated_at=CURRENT_TIMESTAMP
			 WHERE id=?`,
			req.BGGID, req.Title, req.YearPublished, req.MinPlayers, req.MaxPlayers,
			req.Weight, req.ImageURL, req.Description, id,
		)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			jsonError(w, "game not found", http.StatusNotFound)
			return
		}

		var g Game
		db.QueryRowContext(r.Context(),
			`SELECT id, bgg_id, title, year_published, min_players, max_players, weight,
			        image_url, description, created_at, updated_at
			 FROM games WHERE id = ?`, id,
		).Scan(
			&g.ID, &g.BGGID, &g.Title, &g.YearPublished,
			&g.MinPlayers, &g.MaxPlayers, &g.Weight,
			&g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
		)
		jsonOK(w, g, http.StatusOK)
	}
}

// DeleteGame handles DELETE /api/games/{id} (admin).
func DeleteGame(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		result, err := db.ExecContext(r.Context(), `DELETE FROM games WHERE id=?`, id)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			jsonError(w, "game not found", http.StatusNotFound)
			return
		}
		jsonOK(w, map[string]string{"status": "deleted"}, http.StatusOK)
	}
}

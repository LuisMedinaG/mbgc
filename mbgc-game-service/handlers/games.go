package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/luismedinag/mbgc-game-service/models"
	"github.com/luismedinag/mbgc-shared/apierrors"
	"github.com/luismedinag/mbgc-shared/response"
)

func ListGames(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		page, perPage := parsePagination(r)
		offset := (page - 1) * perPage
		q := r.URL.Query().Get("q")

		var (
			rows pgx.Rows
			err  error
			total int
		)

		if q != "" {
			pattern := "%" + q + "%"
			err = db.QueryRow(r.Context(),
				`SELECT COUNT(*) FROM games WHERE title ILIKE $1`, pattern).Scan(&total)
			if err != nil {
				response.InternalError(w)
				return
			}
			rows, err = db.Query(r.Context(),
				`SELECT id, bgg_id, title, year_published, min_players, max_players, weight, image_url, description, created_at, updated_at
				 FROM games WHERE title ILIKE $1 ORDER BY title LIMIT $2 OFFSET $3`,
				pattern, perPage, offset)
		} else {
			err = db.QueryRow(r.Context(), `SELECT COUNT(*) FROM games`).Scan(&total)
			if err != nil {
				response.InternalError(w)
				return
			}
			rows, err = db.Query(r.Context(),
				`SELECT id, bgg_id, title, year_published, min_players, max_players, weight, image_url, description, created_at, updated_at
				 FROM games ORDER BY title LIMIT $1 OFFSET $2`,
				perPage, offset)
		}
		if err != nil {
			response.InternalError(w)
			return
		}
		defer rows.Close()

		games := make([]models.Game, 0)
		for rows.Next() {
			var g models.Game
			if err := rows.Scan(&g.ID, &g.BggID, &g.Title, &g.YearPublished, &g.MinPlayers, &g.MaxPlayers, &g.Weight, &g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt); err != nil {
				response.InternalError(w)
				return
			}
			games = append(games, g)
		}
		if rows.Err() != nil {
			response.InternalError(w)
			return
		}

		response.OK(w, map[string]any{
			"games":    games,
			"total":    total,
			"page":     page,
			"per_page": perPage,
		})
	}
}

func GetGame(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		var g models.Game
		err := db.QueryRow(r.Context(),
			`SELECT id, bgg_id, title, year_published, min_players, max_players, weight, image_url, description, created_at, updated_at
			 FROM games WHERE id = $1`, id).
			Scan(&g.ID, &g.BggID, &g.Title, &g.YearPublished, &g.MinPlayers, &g.MaxPlayers, &g.Weight, &g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				response.NotFound(w)
				return
			}
			response.InternalError(w)
			return
		}
		response.OK(w, g)
	}
}

type gameInput struct {
	BggID         *int     `json:"bgg_id"`
	Title         string   `json:"title"`
	YearPublished *int     `json:"year_published"`
	MinPlayers    *int     `json:"min_players"`
	MaxPlayers    *int     `json:"max_players"`
	Weight        *float64 `json:"weight"`
	ImageURL      *string  `json:"image_url"`
	Description   *string  `json:"description"`
}

func CreateGame(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var input gameInput
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			response.BadRequest(w, "invalid JSON")
			return
		}
		if input.Title == "" {
			response.BadRequest(w, "title is required")
			return
		}

		var g models.Game
		err := db.QueryRow(r.Context(),
			`INSERT INTO games (bgg_id, title, year_published, min_players, max_players, weight, image_url, description)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
			 RETURNING id, bgg_id, title, year_published, min_players, max_players, weight, image_url, description, created_at, updated_at`,
			input.BggID, input.Title, input.YearPublished, input.MinPlayers, input.MaxPlayers, input.Weight, input.ImageURL, input.Description).
			Scan(&g.ID, &g.BggID, &g.Title, &g.YearPublished, &g.MinPlayers, &g.MaxPlayers, &g.Weight, &g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt)
		if err != nil {
			if isUniqueViolation(err) {
				response.Error(w, http.StatusConflict, apierrors.ErrConflict.Error())
				return
			}
			response.InternalError(w)
			return
		}
		response.Created(w, g)
	}
}

func UpdateGame(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		var input gameInput
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			response.BadRequest(w, "invalid JSON")
			return
		}
		if input.Title == "" {
			response.BadRequest(w, "title is required")
			return
		}

		var g models.Game
		err := db.QueryRow(r.Context(),
			`UPDATE games SET bgg_id=$1, title=$2, year_published=$3, min_players=$4, max_players=$5, weight=$6, image_url=$7, description=$8, updated_at=now()
			 WHERE id=$9
			 RETURNING id, bgg_id, title, year_published, min_players, max_players, weight, image_url, description, created_at, updated_at`,
			input.BggID, input.Title, input.YearPublished, input.MinPlayers, input.MaxPlayers, input.Weight, input.ImageURL, input.Description, id).
			Scan(&g.ID, &g.BggID, &g.Title, &g.YearPublished, &g.MinPlayers, &g.MaxPlayers, &g.Weight, &g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				response.NotFound(w)
				return
			}
			if isUniqueViolation(err) {
				response.Error(w, http.StatusConflict, apierrors.ErrConflict.Error())
				return
			}
			response.InternalError(w)
			return
		}
		response.OK(w, g)
	}
}

func DeleteGame(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		tag, err := db.Exec(r.Context(), `DELETE FROM games WHERE id=$1`, id)
		if err != nil {
			response.InternalError(w)
			return
		}
		if tag.RowsAffected() == 0 {
			response.NotFound(w)
			return
		}
		response.OK(w, "deleted")
	}
}

func parsePagination(r *http.Request) (page, perPage int) {
	page, _ = strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	perPage, _ = strconv.Atoi(r.URL.Query().Get("per_page"))
	if perPage < 1 {
		perPage = 20
	}
	if perPage > 100 {
		perPage = 100
	}
	return
}

package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/luismedinag/mbgc-game-service/models"
	"github.com/luismedinag/mbgc-shared/apierrors"
	"github.com/luismedinag/mbgc-shared/middleware"
	"github.com/luismedinag/mbgc-shared/response"
)

func ListCollection(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := middleware.GetClaims(r)
		if claims == nil {
			response.Unauthorized(w)
			return
		}

		page, perPage := parsePagination(r)
		offset := (page - 1) * perPage

		var total int
		if err := db.QueryRow(r.Context(),
			`SELECT COUNT(*) FROM collection_entries WHERE user_id=$1`, claims.UserID).Scan(&total); err != nil {
			response.InternalError(w)
			return
		}

		rows, err := db.Query(r.Context(),
			`SELECT id, user_id, game_id, status, rating, notes, created_at, updated_at
			 FROM collection_entries WHERE user_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
			claims.UserID, perPage, offset)
		if err != nil {
			response.InternalError(w)
			return
		}
		defer rows.Close()

		entries := make([]models.CollectionEntry, 0)
		for rows.Next() {
			var e models.CollectionEntry
			if err := rows.Scan(&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes, &e.CreatedAt, &e.UpdatedAt); err != nil {
				response.InternalError(w)
				return
			}
			entries = append(entries, e)
		}
		if rows.Err() != nil {
			response.InternalError(w)
			return
		}

		response.OK(w, map[string]any{
			"entries":  entries,
			"total":    total,
			"page":     page,
			"per_page": perPage,
		})
	}
}

type collectionInput struct {
	GameID string  `json:"game_id"`
	Status string  `json:"status"`
	Rating *int    `json:"rating"`
	Notes  *string `json:"notes"`
}

func AddToCollection(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := middleware.GetClaims(r)
		if claims == nil {
			response.Unauthorized(w)
			return
		}

		var input collectionInput
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			response.BadRequest(w, "invalid JSON")
			return
		}
		if input.GameID == "" {
			response.BadRequest(w, "game_id is required")
			return
		}
		if input.Status == "" {
			response.BadRequest(w, "status is required")
			return
		}

		var e models.CollectionEntry
		err := db.QueryRow(r.Context(),
			`INSERT INTO collection_entries (user_id, game_id, status, rating, notes)
			 VALUES ($1,$2,$3,$4,$5)
			 RETURNING id, user_id, game_id, status, rating, notes, created_at, updated_at`,
			claims.UserID, input.GameID, input.Status, input.Rating, input.Notes).
			Scan(&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes, &e.CreatedAt, &e.UpdatedAt)
		if err != nil {
			if isUniqueViolation(err) {
				response.Error(w, http.StatusConflict, apierrors.ErrConflict.Error())
				return
			}
			if isForeignKeyViolation(err) {
				response.BadRequest(w, apierrors.ErrGameNotFound.Error())
				return
			}
			response.InternalError(w)
			return
		}
		response.Created(w, e)
	}
}

func UpdateCollectionEntry(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := middleware.GetClaims(r)
		if claims == nil {
			response.Unauthorized(w)
			return
		}

		id := r.PathValue("id")
		var input collectionInput
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			response.BadRequest(w, "invalid JSON")
			return
		}
		if input.Status == "" {
			response.BadRequest(w, "status is required")
			return
		}

		var e models.CollectionEntry
		err := db.QueryRow(r.Context(),
			`UPDATE collection_entries SET status=$1, rating=$2, notes=$3, updated_at=now()
			 WHERE id=$4 AND user_id=$5
			 RETURNING id, user_id, game_id, status, rating, notes, created_at, updated_at`,
			input.Status, input.Rating, input.Notes, id, claims.UserID).
			Scan(&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes, &e.CreatedAt, &e.UpdatedAt)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				response.NotFound(w)
				return
			}
			response.InternalError(w)
			return
		}
		response.OK(w, e)
	}
}

func RemoveFromCollection(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := middleware.GetClaims(r)
		if claims == nil {
			response.Unauthorized(w)
			return
		}

		id := r.PathValue("id")
		tag, err := db.Exec(r.Context(),
			`DELETE FROM collection_entries WHERE id=$1 AND user_id=$2`, id, claims.UserID)
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

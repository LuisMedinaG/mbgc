package handlers

import (
	"errors"
	"io"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/luismedinag/mbgc-game-service/models"
	"github.com/luismedinag/mbgc-shared/middleware"
	"github.com/luismedinag/mbgc-shared/response"
)

const maxUploadSize = 10 << 20 // 10 MB

func ListPlayerAids(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		gameID := r.URL.Query().Get("game_id")

		page, perPage := parsePagination(r)
		offset := (page - 1) * perPage

		var (
			total int
			rows  pgx.Rows
			err   error
		)

		if gameID != "" {
			if err = db.QueryRow(r.Context(),
				`SELECT COUNT(*) FROM player_aids WHERE game_id=$1`, gameID).Scan(&total); err != nil {
				response.InternalError(w)
				return
			}
			rows, err = db.Query(r.Context(),
				`SELECT id, game_id, uploaded_by, filename, content_type, size_bytes, created_at
				 FROM player_aids WHERE game_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
				gameID, perPage, offset)
		} else {
			if err = db.QueryRow(r.Context(),
				`SELECT COUNT(*) FROM player_aids`).Scan(&total); err != nil {
				response.InternalError(w)
				return
			}
			rows, err = db.Query(r.Context(),
				`SELECT id, game_id, uploaded_by, filename, content_type, size_bytes, created_at
				 FROM player_aids ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
				perPage, offset)
		}
		if err != nil {
			response.InternalError(w)
			return
		}
		defer rows.Close()

		aids := make([]models.PlayerAid, 0)
		for rows.Next() {
			var a models.PlayerAid
			if err := rows.Scan(&a.ID, &a.GameID, &a.UploadedBy, &a.Filename, &a.ContentType, &a.SizeBytes, &a.CreatedAt); err != nil {
				response.InternalError(w)
				return
			}
			aids = append(aids, a)
		}
		if rows.Err() != nil {
			response.InternalError(w)
			return
		}

		response.OK(w, map[string]any{
			"player_aids": aids,
			"total":       total,
			"page":        page,
			"per_page":    perPage,
		})
	}
}

func UploadPlayerAid(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := middleware.GetClaims(r)
		if claims == nil {
			response.Unauthorized(w)
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, maxUploadSize)
		if err := r.ParseMultipartForm(maxUploadSize); err != nil {
			response.BadRequest(w, "file too large or invalid multipart form")
			return
		}

		gameID := r.FormValue("game_id")
		if gameID == "" {
			response.BadRequest(w, "game_id is required")
			return
		}

		file, header, err := r.FormFile("file")
		if err != nil {
			response.BadRequest(w, "file is required")
			return
		}
		defer file.Close()

		data, err := io.ReadAll(file)
		if err != nil {
			response.InternalError(w)
			return
		}

		contentType := header.Header.Get("Content-Type")
		if contentType == "" {
			contentType = "application/octet-stream"
		}

		var a models.PlayerAid
		err = db.QueryRow(r.Context(),
			`INSERT INTO player_aids (game_id, uploaded_by, filename, content_type, size_bytes, data)
			 VALUES ($1,$2,$3,$4,$5,$6)
			 RETURNING id, game_id, uploaded_by, filename, content_type, size_bytes, created_at`,
			gameID, claims.UserID, header.Filename, contentType, int64(len(data)), data).
			Scan(&a.ID, &a.GameID, &a.UploadedBy, &a.Filename, &a.ContentType, &a.SizeBytes, &a.CreatedAt)
		if err != nil {
			if isForeignKeyViolation(err) {
				response.BadRequest(w, "game not found")
				return
			}
			response.InternalError(w)
			return
		}
		response.Created(w, a)
	}
}

func DownloadPlayerAid(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")

		var a models.PlayerAid
		err := db.QueryRow(r.Context(),
			`SELECT id, game_id, uploaded_by, filename, content_type, size_bytes, data, created_at
			 FROM player_aids WHERE id=$1`, id).
			Scan(&a.ID, &a.GameID, &a.UploadedBy, &a.Filename, &a.ContentType, &a.SizeBytes, &a.DataForDownload, &a.CreatedAt)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				response.NotFound(w)
				return
			}
			response.InternalError(w)
			return
		}

		w.Header().Set("Content-Type", a.ContentType)
		w.Header().Set("Content-Disposition", `attachment; filename="`+a.Filename+`"`)
		w.WriteHeader(http.StatusOK)
		w.Write(a.DataForDownload) //nolint:errcheck
	}
}

func DeletePlayerAid(db *pgx.Conn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := middleware.GetClaims(r)
		if claims == nil {
			response.Unauthorized(w)
			return
		}

		id := r.PathValue("id")

		// Only the uploader or an admin may delete
		var uploadedBy string
		err := db.QueryRow(r.Context(),
			`SELECT uploaded_by FROM player_aids WHERE id=$1`, id).Scan(&uploadedBy)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				response.NotFound(w)
				return
			}
			response.InternalError(w)
			return
		}
		if uploadedBy != claims.UserID && claims.Role != "admin" {
			response.Error(w, http.StatusForbidden, "forbidden")
			return
		}

		tag, err := db.Exec(r.Context(), `DELETE FROM player_aids WHERE id=$1`, id)
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

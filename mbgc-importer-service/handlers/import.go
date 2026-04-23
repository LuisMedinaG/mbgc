package handlers

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	bggclient "github.com/luismedinag/mbgc-importer-service/bgg"
	csvimporter "github.com/luismedinag/mbgc-importer-service/csv"
	"github.com/luismedinag/mbgc-shared/response"
)

// createJob inserts a new import_job row and returns its UUID.
func createJob(ctx context.Context, pool *pgxpool.Pool, userID, jobType string) (string, error) {
	var id string
	err := pool.QueryRow(ctx, `
		INSERT INTO import_jobs (user_id, type, status)
		VALUES ($1, $2, 'pending')
		RETURNING id
	`, userID, jobType).Scan(&id)
	return id, err
}

// setJobRunning marks a job as running with a known total.
func setJobRunning(pool *pgxpool.Pool, jobID string, total int) {
	_, _ = pool.Exec(context.Background(), `
		UPDATE import_jobs SET status = 'running', total_items = $1, updated_at = now()
		WHERE id = $2
	`, total, jobID)
}

// setJobDone marks a job as done.
func setJobDone(pool *pgxpool.Pool, jobID string, processed int) {
	_, _ = pool.Exec(context.Background(), `
		UPDATE import_jobs SET status = 'done', processed_items = $1, updated_at = now()
		WHERE id = $2
	`, processed, jobID)
}

// setJobFailed marks a job as failed with an error message.
func setJobFailed(pool *pgxpool.Pool, jobID, errMsg string) {
	_, _ = pool.Exec(context.Background(), `
		UPDATE import_jobs SET status = 'failed', error_message = $1, updated_at = now()
		WHERE id = $2
	`, errMsg, jobID)
}

// TriggerBGGImport handles POST /import/bgg.
// Body: {"bgg_username": "..."}
func TriggerBGGImport(pool *pgxpool.Pool, gameServiceURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		if userID == "" {
			response.Unauthorized(w)
			return
		}

		var body struct {
			BGGUsername string `json:"bgg_username"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.BGGUsername == "" {
			response.BadRequest(w, "bgg_username is required")
			return
		}

		jobID, err := createJob(r.Context(), pool, userID, "bgg")
		if err != nil {
			response.InternalError(w)
			return
		}

		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
			defer cancel()

			games, err := bggclient.SearchGames(ctx, body.BGGUsername)
			if err != nil {
				slog.Error("BGG fetch failed", "job_id", jobID, "error", err)
				setJobFailed(pool, jobID, err.Error())
				return
			}

			setJobRunning(pool, jobID, len(games))

			for i, g := range games {
				// TODO: POST each game to game-service:
				//   POST {gameServiceURL}/games
				//   Body: {"bgg_id": g.BGGID, "title": g.Title, "year_published": g.YearPublished,
				//          "min_players": g.MinPlayers, "max_players": g.MaxPlayers,
				//          "weight": g.Weight, "image_url": g.ImageURL}
				slog.Info("would import BGG game", "job_id", jobID, "index", i,
					"bgg_id", g.BGGID, "title", g.Title)
			}

			setJobDone(pool, jobID, len(games))
			slog.Info("BGG import complete", "job_id", jobID, "games", len(games))
		}()

		response.Created(w, map[string]string{"job_id": jobID})
	}
}

// TriggerCSVImport handles POST /import/csv.
// Expects multipart form with a "file" field containing the CSV.
func TriggerCSVImport(pool *pgxpool.Pool, gameServiceURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		if userID == "" {
			response.Unauthorized(w)
			return
		}

		if err := r.ParseMultipartForm(10 << 20); err != nil { // 10 MB limit
			response.BadRequest(w, "failed to parse multipart form")
			return
		}

		file, _, err := r.FormFile("file")
		if err != nil {
			response.BadRequest(w, "file field is required")
			return
		}
		defer file.Close()

		games, err := csvimporter.ParseCSV(file)
		if err != nil {
			response.BadRequest(w, "invalid CSV: "+err.Error())
			return
		}

		jobID, err := createJob(r.Context(), pool, userID, "csv")
		if err != nil {
			response.InternalError(w)
			return
		}

		// Snapshot games for the goroutine.
		gamesCopy := games

		go func() {
			setJobRunning(pool, jobID, len(gamesCopy))

			for i, g := range gamesCopy {
				// TODO: POST each game to game-service:
				//   POST {gameServiceURL}/games
				//   Body: {"bgg_id": g.BGGID, "title": g.Title, "year": g.Year,
				//          "min_players": g.MinPlayers, "max_players": g.MaxPlayers}
				slog.Info("would import CSV game", "job_id", jobID, "index", i,
					"bgg_id", g.BGGID, "title", g.Title)
			}

			setJobDone(pool, jobID, len(gamesCopy))
			slog.Info("CSV import complete", "job_id", jobID, "games", len(gamesCopy))
		}()

		response.Created(w, map[string]string{"job_id": jobID})
	}
}

// GetImportJob handles GET /import/jobs/{id}.
func GetImportJob(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		if userID == "" {
			response.Unauthorized(w)
			return
		}

		jobID := r.PathValue("id")
		if jobID == "" {
			response.BadRequest(w, "missing job id")
			return
		}

		var job struct {
			ID             string  `json:"id"`
			UserID         string  `json:"user_id"`
			Type           string  `json:"type"`
			Status         string  `json:"status"`
			TotalItems     *int    `json:"total_items"`
			ProcessedItems int     `json:"processed_items"`
			ErrorMessage   *string `json:"error_message"`
		}

		err := pool.QueryRow(r.Context(), `
			SELECT id, user_id, type, status, total_items, processed_items, error_message
			FROM import_jobs WHERE id = $1
		`, jobID).Scan(&job.ID, &job.UserID, &job.Type, &job.Status,
			&job.TotalItems, &job.ProcessedItems, &job.ErrorMessage)
		if err != nil {
			response.NotFound(w)
			return
		}

		// Only the owning user (or admin) may view the job.
		role := r.Header.Get("X-User-Role")
		if job.UserID != userID && role != "admin" {
			response.Forbidden(w)
			return
		}

		response.OK(w, job)
	}
}

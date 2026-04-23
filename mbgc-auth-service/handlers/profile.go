package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/luismedinag/mbgc-auth-service/models"
	"github.com/luismedinag/mbgc-shared/response"
)

// upsertProfile ensures a profile row exists for the given user, creating it if absent.
func upsertProfile(r *http.Request, pool *pgxpool.Pool, userID, email string) (*models.Profile, error) {
	_, err := pool.Exec(r.Context(), `
		INSERT INTO profiles (user_id, email)
		VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email, updated_at = now()
	`, userID, email)
	if err != nil {
		return nil, err
	}
	return getProfileByID(r, pool, userID)
}

func getProfileByID(r *http.Request, pool *pgxpool.Pool, userID string) (*models.Profile, error) {
	row := pool.QueryRow(r.Context(), `
		SELECT user_id, email, bgg_username, role, import_quota, imports_used, created_at, updated_at
		FROM profiles WHERE user_id = $1
	`, userID)

	p := &models.Profile{}
	err := row.Scan(&p.UserID, &p.Email, &p.BGGUsername, &p.Role,
		&p.ImportQuota, &p.ImportsUsed, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return p, nil
}

// GetProfile handles GET /profile — returns the authenticated user's profile.
// Auto-creates profile on first access.
func GetProfile(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		email := r.Header.Get("X-User-Email")
		if userID == "" {
			response.Unauthorized(w)
			return
		}

		p, err := upsertProfile(r, pool, userID, email)
		if err != nil {
			response.InternalError(w)
			return
		}
		response.OK(w, p)
	}
}

// UpdateProfile handles PUT /profile — updates bgg_username.
func UpdateProfile(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		email := r.Header.Get("X-User-Email")
		if userID == "" {
			response.Unauthorized(w)
			return
		}

		var body struct {
			BGGUsername *string `json:"bgg_username"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			response.BadRequest(w, "invalid JSON body")
			return
		}

		// Ensure profile exists first.
		if _, err := upsertProfile(r, pool, userID, email); err != nil {
			response.InternalError(w)
			return
		}

		_, err := pool.Exec(r.Context(), `
			UPDATE profiles SET bgg_username = $1, updated_at = now() WHERE user_id = $2
		`, body.BGGUsername, userID)
		if err != nil {
			response.InternalError(w)
			return
		}

		p, err := getProfileByID(r, pool, userID)
		if err != nil {
			response.InternalError(w)
			return
		}
		response.OK(w, p)
	}
}

// GetAnyProfile handles GET /profile/{user_id} — admin only.
func GetAnyProfile(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		targetID := r.PathValue("user_id")
		if targetID == "" {
			response.BadRequest(w, "missing user_id")
			return
		}

		p, err := getProfileByID(r, pool, targetID)
		if err != nil {
			if err == pgx.ErrNoRows {
				response.NotFound(w)
				return
			}
			response.InternalError(w)
			return
		}
		response.OK(w, p)
	}
}

// ListProfiles handles GET /profiles — admin only, with pagination.
func ListProfiles(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		page := 1
		perPage := 20

		if v := r.URL.Query().Get("page"); v != "" {
			if n, err := strconv.Atoi(v); err == nil && n > 0 {
				page = n
			}
		}
		if v := r.URL.Query().Get("per_page"); v != "" {
			if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 100 {
				perPage = n
			}
		}
		offset := (page - 1) * perPage

		var total int
		if err := pool.QueryRow(r.Context(), `SELECT COUNT(*) FROM profiles`).Scan(&total); err != nil {
			response.InternalError(w)
			return
		}

		rows, err := pool.Query(r.Context(), `
			SELECT user_id, email, bgg_username, role, import_quota, imports_used, created_at, updated_at
			FROM profiles ORDER BY created_at DESC LIMIT $1 OFFSET $2
		`, perPage, offset)
		if err != nil {
			response.InternalError(w)
			return
		}
		defer rows.Close()

		profiles := make([]*models.Profile, 0)
		for rows.Next() {
			p := &models.Profile{}
			if err := rows.Scan(&p.UserID, &p.Email, &p.BGGUsername, &p.Role,
				&p.ImportQuota, &p.ImportsUsed, &p.CreatedAt, &p.UpdatedAt); err != nil {
				response.InternalError(w)
				return
			}
			profiles = append(profiles, p)
		}
		if rows.Err() != nil {
			response.InternalError(w)
			return
		}

		response.OK(w, map[string]any{
			"profiles": profiles,
			"total":    total,
			"page":     page,
			"per_page": perPage,
		})
	}
}

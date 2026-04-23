package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"time"

	appauth "github.com/luismedinag/myboardgamecollection/auth"
)

type registerRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type userResponse struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Role  string `json:"role"`
}

type authResponse struct {
	Token string       `json:"token"`
	User  userResponse `json:"user"`
}

// Register handles POST /api/auth/register.
func Register(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req registerRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid request body", http.StatusBadRequest)
			return
		}
		if req.Email == "" || req.Password == "" {
			jsonError(w, "email and password required", http.StatusBadRequest)
			return
		}

		hash, err := appauth.HashPassword(req.Password)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		id := newID()
		_, err = db.ExecContext(r.Context(),
			`INSERT INTO users (id, email, password_hash, role) VALUES (?, ?, ?, 'user')`,
			id, req.Email, hash,
		)
		if err != nil {
			jsonError(w, "email already registered", http.StatusConflict)
			return
		}

		secret := jwtSecret()
		token, err := appauth.GenerateToken(id, req.Email, "user", secret, 15*time.Minute)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, authResponse{
			Token: token,
			User:  userResponse{ID: id, Email: req.Email, Role: "user"},
		}, http.StatusCreated)
	}
}

// Login handles POST /api/auth/login.
func Login(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req loginRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid request body", http.StatusBadRequest)
			return
		}

		var id, hash, role string
		err := db.QueryRowContext(r.Context(),
			`SELECT id, password_hash, role FROM users WHERE email = ?`, req.Email,
		).Scan(&id, &hash, &role)
		if err != nil {
			jsonError(w, "invalid credentials", http.StatusUnauthorized)
			return
		}

		if !appauth.CheckPassword(hash, req.Password) {
			jsonError(w, "invalid credentials", http.StatusUnauthorized)
			return
		}

		secret := jwtSecret()
		token, err := appauth.GenerateToken(id, req.Email, role, secret, 15*time.Minute)
		if err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, authResponse{
			Token: token,
			User:  userResponse{ID: id, Email: req.Email, Role: role},
		}, http.StatusOK)
	}
}

// jwtSecret returns the JWT secret from the environment.
func jwtSecret() string {
	s := os.Getenv("JWT_SECRET")
	if s == "" {
		return "changeme"
	}
	return s
}

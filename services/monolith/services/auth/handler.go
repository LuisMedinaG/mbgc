package auth

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

// Handler serves all auth-related API routes.
type Handler struct {
	store     *Store
	jwtSecret string
	limiter   *httpx.LoginLimiter
}

// NewHandler creates a new auth handler.
func NewHandler(store *Store, jwtSecret string, limiter *httpx.LoginLimiter) *Handler {
	return &Handler{store: store, jwtSecret: jwtSecret, limiter: limiter}
}

// Login authenticates a user and returns access + refresh tokens.
//
// POST /api/v1/auth/login
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if body.Username == "" || body.Password == "" {
		writeError(w, http.StatusBadRequest, "username and password required")
		return
	}

	userID, err := h.store.AuthenticateUser(body.Username, body.Password)
	if err != nil {
		if h.limiter != nil {
			h.limiter.Record(httpx.ClientIP(r))
		}
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	_, isAdmin, err := h.store.GetUserInfo(userID)
	if err != nil {
		slog.Error("auth.Login: GetUserInfo", "user_id", userID, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	accessToken, err := httpx.GenerateAccessToken(userID, body.Username, isAdmin, h.jwtSecret)
	if err != nil {
		slog.Error("auth.Login: GenerateAccessToken", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	refreshToken, err := h.store.CreateAPIRefreshToken(userID)
	if err != nil {
		slog.Error("auth.Login: CreateAPIRefreshToken", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
		"expires_in":    900,
	})
}

// Refresh issues a new access token using a valid refresh token.
//
// POST /api/v1/auth/refresh
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if body.RefreshToken == "" {
		writeError(w, http.StatusBadRequest, "refresh_token required")
		return
	}

	userID, username, isAdmin, err := h.store.ValidateAPIRefreshToken(body.RefreshToken)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid or expired refresh token")
		return
	}

	accessToken, err := httpx.GenerateAccessToken(userID, username, isAdmin, h.jwtSecret)
	if err != nil {
		slog.Error("auth.Refresh: GenerateAccessToken", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{
		"access_token": accessToken,
		"expires_in":   900,
	})
}

// Logout revokes a refresh token.
//
// POST /api/v1/auth/logout
func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if body.RefreshToken != "" {
		if err := h.store.DeleteAPIRefreshToken(body.RefreshToken); err != nil {
			slog.Error("auth.Logout: DeleteAPIRefreshToken", "error", err)
		}
	}
	writeData(w, http.StatusOK, map[string]any{"ok": true})
}

// Ping confirms JWT auth is working.
//
// GET /api/v1/ping
func (h *Handler) Ping(w http.ResponseWriter, r *http.Request) {
	username := httpx.UsernameFromContext(r.Context())
	writeData(w, http.StatusOK, map[string]any{
		"pong":     true,
		"username": username,
	})
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

func writeData(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": v})
}

func writeError(w http.ResponseWriter, status int, msg string) {
	httpx.WriteJSONError(w, status, msg)
}

// Package profile handles user profile API routes.
package profile

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/monolith/shared/apierr"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

// Store is the subset of auth store the profile handler needs.
type Store interface {
	GetBGGUsername(userID int64) (string, error)
	SetBGGUsername(userID int64, bggUsername string) error
	ChangePassword(userID int64, currentPassword, newPassword string) error
}

// Handler serves profile API routes.
type Handler struct{ store Store }

// NewHandler creates a new profile handler.
func NewHandler(store Store) *Handler { return &Handler{store: store} }

// GetProfile returns the authenticated user's profile info.
//
// GET /api/v1/profile
func (h *Handler) GetProfile(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	username := httpx.UsernameFromContext(r.Context())
	bggUsername, err := h.store.GetBGGUsername(userID)
	if err != nil {
		slog.Error("profile.GetProfile: GetBGGUsername", "error", err)
	}
	writeData(w, http.StatusOK, map[string]any{
		"username":     username,
		"bgg_username": bggUsername,
	})
}

// SetBGGUsername updates the user's BGG username.
//
// PUT /api/v1/profile/bgg-username
func (h *Handler) SetBGGUsername(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		BGGUsername string `json:"bgg_username"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.store.SetBGGUsername(userID, strings.TrimSpace(body.BGGUsername)); err != nil {
		slog.Error("profile.SetBGGUsername", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{"bgg_username": strings.TrimSpace(body.BGGUsername)})
}

// ChangePassword changes the user's password after verifying the current one.
//
// PUT /api/v1/profile/password
func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}

	var body struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if body.CurrentPassword == "" || body.NewPassword == "" {
		writeError(w, http.StatusBadRequest, "current_password and new_password required")
		return
	}
	if len(body.NewPassword) < 8 {
		writeError(w, http.StatusBadRequest, "new password must be at least 8 characters")
		return
	}

	if err := h.store.ChangePassword(userID, body.CurrentPassword, body.NewPassword); err != nil {
		if errors.Is(err, apierr.ErrWrongPassword) {
			writeError(w, http.StatusForbidden, "current password incorrect")
			return
		}
		slog.Error("profile.ChangePassword", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── Request / response helpers ────────────────────────────────────────────────

func requireUserID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return 0, false
	}
	return id, true
}

func writeData(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": v})
}

func writeError(w http.ResponseWriter, status int, msg string) {
	httpx.WriteJSONError(w, status, msg)
}

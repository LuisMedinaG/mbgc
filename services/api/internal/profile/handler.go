package profile

import (
	"encoding/json"
	"net/http"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	// ref: profile.VIEW.1 — GET /api/v1/profile
	mux.Handle("GET /api/v1/profile", auth(http.HandlerFunc(h.GetProfile)))
	// ref: profile.BGG_USERNAME.1 — PUT /api/v1/profile/bgg-username
	mux.Handle("PUT /api/v1/profile/bgg-username", auth(http.HandlerFunc(h.SetBGGUsername)))
}

func (h *Handler) GetProfile(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	profile, err := h.svc.GetProfile(r.Context(), userID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.New(profile))
}

// ref: profile.BGG_USERNAME.1 — set/update/clear BGG username via PUT /api/v1/profile/bgg-username
// ref: api-layer.CONFIG.7 — cap user-supplied strings at 255 chars before persistence
func (h *Handler) SetBGGUsername(w http.ResponseWriter, r *http.Request) {
	userID, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}
	var body struct {
		BGGUsername string `json:"bgg_username"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpx.WriteError(w, apierr.ErrBadRequest)
		return
	}
	body.BGGUsername = httpx.Truncate(body.BGGUsername, 255)
	if err := h.svc.SetBGGUsername(r.Context(), userID, body.BGGUsername); err != nil {
		httpx.WriteError(w, err)
		return
	}
	profile, err := h.svc.GetProfile(r.Context(), userID)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, httpx.New(profile))
}

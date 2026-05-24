package handler

import (
	"encoding/json"
	"net/http"

	"github.com/LuisMedinaG/mbgc/services/auth/internal/service"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	svc *service.Service
}

func New(svc *service.Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/profile", h.GetProfile)
	mux.HandleFunc("PUT /api/v1/profile/bgg-username", h.SetBGGUsername)
	// Note: password change is handled client-side via the Supabase Auth SDK
}

// GetProfile godoc
//
//	@Summary     Get current user profile
//	@Tags        profile
//	@Produce     json
//	@Success     200  {object}  envelope.Response[model.Profile]
//	@Failure     401  {object}  envelope.ErrorResponse
//	@Router      /profile [get]
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
	httpx.WriteJSON(w, http.StatusOK, envelope.New(profile))
}

// SetBGGUsername godoc
//
//	@Summary     Update BGG username
//	@Tags        profile
//	@Accept      json
//	@Produce     json
//	@Param       body  body      object{bgg_username=string}  true  "BGG username"
//	@Success     204
//	@Failure     400  {object}  envelope.ErrorResponse
//	@Failure     401  {object}  envelope.ErrorResponse
//	@Router      /profile/bgg-username [put]
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
	if err := h.svc.SetBGGUsername(r.Context(), userID, body.BGGUsername); err != nil {
		httpx.WriteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

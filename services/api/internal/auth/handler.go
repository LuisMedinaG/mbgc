package auth

import (
	"net/http"

	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	store *Store
}

func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.HandleFunc("GET /api/v1/ping", auth(http.HandlerFunc(h.ping)).ServeHTTP)
}

func (h *Handler) ping(w http.ResponseWriter, r *http.Request) {
	username := httpx.UsernameFromContext(r.Context())

	httpx.WriteJSON(w, http.StatusOK, envelope.Response[map[string]interface{}]{
		Data: map[string]interface{}{
			"pong":     true,
			"username": username,
		},
	})
}

package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
	"github.com/LuisMedinaG/mbgc/services/api/internal/supabase"
)

// userStore resolves identifiers to emails. Handler depends on the
// interface (not *Store) so handler tests can run without a database.
type userStore interface {
	EmailByUsername(ctx context.Context, username string) (string, error)
	EmailByUserID(ctx context.Context, userID string) (string, error)
}

type Handler struct {
	store    userStore
	supabase *supabase.Client
}

func NewHandler(store userStore, supabaseURL, apiKey string, client *http.Client) *Handler {
	if client == nil {
		client = httpx.DefaultClient
	}
	return &Handler{
		store:    store,
		supabase: supabase.New(supabaseURL, apiKey, client),
	}
}

// ref: api-layer.SEC.5 — rateLimit middleware applied to login/refresh/logout (not auth'd)
func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth, rateLimit func(http.Handler) http.Handler) {
	mux.Handle("POST /api/v1/auth/login", rateLimit(http.HandlerFunc(h.login)))
	mux.Handle("POST /api/v1/auth/refresh", rateLimit(http.HandlerFunc(h.refresh)))
	mux.Handle("POST /api/v1/auth/logout", rateLimit(http.HandlerFunc(h.logout)))
	mux.Handle("GET /api/v1/ping", auth(http.HandlerFunc(h.ping)))
	mux.Handle("PUT /api/v1/auth/password", auth(http.HandlerFunc(h.changePassword))) // ref: auth.CHANGE_PASSWORD.1
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type tokenData struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Username == "" || req.Password == "" {
		httpx.WriteError(w, fmt.Errorf("%w: invalid request body", apierr.ErrBadRequest))
		return
	}

	// ref: auth.LOGIN.3 — resolve username to email; return generic error on miss to prevent enumeration
	// Accept either email or username. If a username (no @), resolve it to an
	// email via an indexed DB lookup. A miss returns the same error as a wrong
	// password so we never reveal whether a username exists.
	authEmail := req.Username
	if !strings.Contains(req.Username, "@") {
		email, err := h.store.EmailByUsername(r.Context(), req.Username)
		if err != nil {
			httpx.WriteError(w, apierr.ErrWrongPassword)
			return
		}
		authEmail = email
	}

	status, respBody, err := h.supabase.DoRequest(r.Context(), http.MethodPost,
		"/auth/v1/token?grant_type=password",
		map[string]string{"email": authEmail, "password": req.Password})

	if err != nil {
		httpx.WriteError(w, err)
		return
	}

	if status != http.StatusOK {
		httpx.WriteError(w, apierr.ErrWrongPassword)
		return
	}

	var result tokenData
	if err := json.Unmarshal(respBody, &result); err != nil {
		httpx.WriteError(w, fmt.Errorf("decode supabase response: %w", err))
		return
	}

	httpx.WriteJSON(w, http.StatusOK, httpx.Response[tokenData]{Data: result})
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		httpx.WriteError(w, fmt.Errorf("%w: missing refresh_token", apierr.ErrBadRequest))
		return
	}

	status, respBody, err := h.supabase.DoRequest(r.Context(), http.MethodPost,
		"/auth/v1/token?grant_type=refresh_token",
		map[string]string{"refresh_token": req.RefreshToken})

	if err != nil {
		httpx.WriteError(w, err)
		return
	}

	if status != http.StatusOK {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}

	var result tokenData
	if err := json.Unmarshal(respBody, &result); err != nil {
		httpx.WriteError(w, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, httpx.Response[tokenData]{Data: result})
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var req logoutRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	_, _, err := h.supabase.DoRequest(r.Context(), http.MethodPost,
		"/auth/v1/logout?scope=global",
		map[string]string{"refresh_token": req.RefreshToken})

	// logout is best-effort; errors are not actionable to client
	if err != nil {
		slog.Debug("logout: request failed", "error", err)
	}

	w.WriteHeader(http.StatusNoContent)
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// ref: auth.CHANGE_PASSWORD.1 — verifies current password then updates via Supabase user endpoint
func (h *Handler) changePassword(w http.ResponseWriter, r *http.Request) {
	var req changePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, fmt.Errorf("%w: invalid request body", apierr.ErrBadRequest))
		return
	}
	if req.CurrentPassword == "" || req.NewPassword == "" {
		httpx.WriteError(w, fmt.Errorf("%w: current_password and new_password are required", apierr.ErrBadRequest))
		return
	}
	if len(req.NewPassword) < 8 {
		httpx.WriteError(w, fmt.Errorf("%w: new_password must be at least 8 characters", apierr.ErrBadRequest))
		return
	}

	userID, _ := httpx.UserIDFromContext(r.Context())
	email, err := h.store.EmailByUserID(r.Context(), userID)
	if err != nil {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}

	// Verify current password via token grant before allowing update.
	status, _, err := h.supabase.DoRequest(r.Context(), http.MethodPost,
		"/auth/v1/token?grant_type=password",
		map[string]string{"email": email, "password": req.CurrentPassword})
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if status != http.StatusOK {
		httpx.WriteError(w, apierr.ErrWrongPassword)
		return
	}

	bearerToken := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	status, _, err = h.supabase.DoRequestWithBearer(r.Context(), http.MethodPut,
		"/auth/v1/user",
		map[string]string{"password": req.NewPassword},
		bearerToken)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	if status != http.StatusOK {
		httpx.WriteError(w, apierr.ErrInternal)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) ping(w http.ResponseWriter, r *http.Request) {
	username := httpx.UsernameFromContext(r.Context())

	httpx.WriteJSON(w, http.StatusOK, httpx.Response[map[string]interface{}]{
		Data: map[string]interface{}{
			"pong":     true,
			"username": username,
		},
	})
}

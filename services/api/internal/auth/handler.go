package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type supabaseAuthClient struct {
	url    string
	apiKey string
	client *http.Client
}

type Handler struct {
	store    *Store
	supabase *supabaseAuthClient
}

func NewHandler(store *Store, supabaseURL, apiKey string, client *http.Client) *Handler {
	return &Handler{
		store: store,
		supabase: &supabaseAuthClient{
			url:    strings.TrimSuffix(supabaseURL, "/"),
			apiKey: apiKey,
			client: client,
		},
	}
}

func (s *supabaseAuthClient) doRequest(ctx context.Context, method, path string, body map[string]string) (int, []byte, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return 0, nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, method, s.url+path, bytes.NewReader(payload))
	if err != nil {
		return 0, nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", s.apiKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp.StatusCode, nil, fmt.Errorf("read response: %w", err)
	}

	return resp.StatusCode, respBody, nil
}

// ref: api-layer.SEC.5 — rateLimit middleware applied to login/refresh/logout (not auth'd)
func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth, rateLimit func(http.Handler) http.Handler) {
	mux.Handle("POST /api/v1/auth/login", rateLimit(http.HandlerFunc(h.login)))
	mux.Handle("POST /api/v1/auth/refresh", rateLimit(http.HandlerFunc(h.refresh)))
	mux.Handle("POST /api/v1/auth/logout", rateLimit(http.HandlerFunc(h.logout)))
	mux.Handle("GET /api/v1/ping", auth(http.HandlerFunc(h.ping)))
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

	status, respBody, err := h.supabase.doRequest(r.Context(), http.MethodPost,
		"/auth/v1/token?grant_type=password",
		map[string]string{"email": req.Username, "password": req.Password})

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

	httpx.WriteJSON(w, http.StatusOK, envelope.Response[tokenData]{Data: result})
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

	status, respBody, err := h.supabase.doRequest(r.Context(), http.MethodPost,
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

	httpx.WriteJSON(w, http.StatusOK, envelope.Response[tokenData]{Data: result})
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var req logoutRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	_, _, err := h.supabase.doRequest(r.Context(), http.MethodPost,
		"/auth/v1/logout?scope=global",
		map[string]string{"refresh_token": req.RefreshToken})

	// logout is best-effort; errors are not actionable to client
	if err != nil {
		slog.Debug("logout: request failed", "error", err)
	}

	w.WriteHeader(http.StatusNoContent)
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

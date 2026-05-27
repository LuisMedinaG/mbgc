package auth

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

type Handler struct {
	store       *Store
	supabaseURL string
	apiKey      string
}

func NewHandler(store *Store, supabaseURL, apiKey string) *Handler {
	return &Handler{
		store:       store,
		supabaseURL: strings.TrimSuffix(supabaseURL, "/"),
		apiKey:      apiKey,
	}
}

func (h *Handler) RegisterRoutes(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.HandleFunc("POST /api/v1/auth/login", h.login)
	mux.HandleFunc("POST /api/v1/auth/refresh", h.refresh)
	mux.HandleFunc("POST /api/v1/auth/logout", h.logout)
	mux.HandleFunc("GET /api/v1/ping", auth(http.HandlerFunc(h.ping)).ServeHTTP)
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

	body, _ := json.Marshal(map[string]string{"email": req.Username, "password": req.Password})
	supaReq, _ := http.NewRequestWithContext(r.Context(), http.MethodPost,
		h.supabaseURL+"/auth/v1/token?grant_type=password", bytes.NewReader(body))
	supaReq.Header.Set("Content-Type", "application/json")
	supaReq.Header.Set("apikey", h.apiKey)

	resp, err := http.DefaultClient.Do(supaReq)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		httpx.WriteError(w, apierr.ErrWrongPassword)
		return
	}

	var result tokenData
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
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

	body, _ := json.Marshal(map[string]string{"refresh_token": req.RefreshToken})
	supaReq, _ := http.NewRequestWithContext(r.Context(), http.MethodPost,
		h.supabaseURL+"/auth/v1/token?grant_type=refresh_token", bytes.NewReader(body))
	supaReq.Header.Set("Content-Type", "application/json")
	supaReq.Header.Set("apikey", h.apiKey)

	resp, err := http.DefaultClient.Do(supaReq)
	if err != nil {
		httpx.WriteError(w, err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		httpx.WriteError(w, apierr.ErrUnauthorized)
		return
	}

	var result tokenData
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
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
	json.NewDecoder(r.Body).Decode(&req) //nolint:errcheck

	accessToken := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")

	body, _ := json.Marshal(map[string]string{"refresh_token": req.RefreshToken})
	supaReq, _ := http.NewRequestWithContext(r.Context(), http.MethodPost,
		h.supabaseURL+"/auth/v1/logout?scope=global", bytes.NewReader(body))
	supaReq.Header.Set("Content-Type", "application/json")
	supaReq.Header.Set("apikey", h.apiKey)
	if accessToken != "" {
		supaReq.Header.Set("Authorization", "Bearer "+accessToken)
	}

	http.DefaultClient.Do(supaReq) //nolint:errcheck — best-effort
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

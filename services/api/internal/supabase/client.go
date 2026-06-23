package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/api/internal/httpx"
)

// Client wraps Supabase HTTP API calls (token grant, refresh, user updates).
type Client struct {
	url    string
	apiKey string
	client *http.Client
}

// New creates a Supabase client for auth operations.
func New(baseURL, apiKey string, hc *http.Client) *Client {
	if hc == nil {
		hc = httpx.DefaultClient
	}
	return &Client{
		url:    strings.TrimSuffix(baseURL, "/"),
		apiKey: apiKey,
		client: hc,
	}
}

// DoRequest calls a Supabase endpoint. Pass a non-empty bearer to include
// Authorization: Bearer (required for user-scoped endpoints like PUT /auth/v1/user).
func (c *Client) DoRequest(ctx context.Context, method, path string, body map[string]string, bearer string) (int, []byte, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return 0, nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.url+path, bytes.NewReader(payload))
	if err != nil {
		return 0, nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", c.apiKey)
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}

	resp, err := c.client.Do(req)
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

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

// Upload uploads a file to Supabase Storage.
// path should be "bucket/filename".
func (c *Client) Upload(ctx context.Context, bucket, filename string, content io.Reader, contentType string) error {
	path := fmt.Sprintf("/storage/v1/object/%s/%s", bucket, filename)
	req, err := http.NewRequestWithContext(ctx, "POST", c.url+path, content)
	if err != nil {
		return fmt.Errorf("create upload request: %w", err)
	}

	req.Header.Set("apikey", c.apiKey)
	req.Header.Set("Authorization", "Bearer "+c.apiKey) // Use service role key
	req.Header.Set("Content-Type", contentType)

	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("upload failed (%d): %s", resp.StatusCode, string(body))
	}

	return nil
}

// Remove deletes a file from Supabase Storage.
func (c *Client) Remove(ctx context.Context, bucket, filename string) error {
	path := fmt.Sprintf("/storage/v1/object/%s", bucket)
	body := map[string][]string{
		"prefixes": {filename},
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal remove request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "DELETE", c.url+path, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("create remove request: %w", err)
	}

	req.Header.Set("apikey", c.apiKey)
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("remove failed (%d): %s", resp.StatusCode, string(respBody))
	}

	return nil
}

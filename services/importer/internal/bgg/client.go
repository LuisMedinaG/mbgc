// Package bgg wraps the BoardGameGeek API.
// It is optional — if no BGG_TOKEN or BGG_COOKIE is set, NewClient returns nil
// and sync operations are disabled.
package bgg

import "net/http"

// Client is a BGG API client. Nil is valid — callers must check before use.
type Client struct {
	httpClient *http.Client
	token      string
	cookie     string
}

// NewClient creates a BGG client. Returns nil if neither token nor cookie is set.
func NewClient(token, cookie string) *Client {
	if token == "" && cookie == "" {
		return nil
	}
	return &Client{
		httpClient: &http.Client{},
		token:      token,
		cookie:     cookie,
	}
}

// Available reports whether BGG credentials are configured.
func (c *Client) Available() bool {
	return c != nil
}

// TODO: implement FetchCollection(bggUsername string) ([]bggGame, error)
// TODO: implement FetchGamesByID(bggIDs []int) ([]bggGame, error)

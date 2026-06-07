package importer

import (
	"net/http"

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// Client wraps the BGG API. Nil is valid — callers must check Available().
type Client struct {
	httpClient *http.Client
	token      string
	cookie     string
}

// NewClient returns nil if neither token nor cookie is set.
func NewClient(token, cookie string) *Client {
	if token == "" && cookie == "" {
		return nil
	}
	return &Client{httpClient: httpx.DefaultClient, token: token, cookie: cookie}
}

// Available reports whether BGG credentials are configured.
func (c *Client) Available() bool {
	return c != nil
}

// TODO: implement FetchCollection(bggUsername string) ([]bggGame, error)
// TODO: implement FetchGamesByID(bggIDs []int) ([]bggGame, error)

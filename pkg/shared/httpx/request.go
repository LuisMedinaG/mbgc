package httpx

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

// DecodeJSON decodes the request body into v, returning a wrapped ErrBadRequest on failure.
func DecodeJSON(r *http.Request, v any) error {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		return fmt.Errorf("%w: invalid request body", apierr.ErrBadRequest)
	}
	return nil
}

// QueryInt returns the integer value of a query parameter or fallback if missing/invalid.
func QueryInt(r *http.Request, key string, fallback int) int {
	s := r.URL.Query().Get(key)
	if s == "" {
		return fallback
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return fallback
	}
	return n
}

// Truncate returns s[:max] if len(s) > max, else s.
func Truncate(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}

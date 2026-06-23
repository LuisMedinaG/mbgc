package httpx

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/go-playground/validator/v10"
)

var validate = validator.New()

// DecodeValidate decodes a JSON body and validates the struct using go-playground/validator.
// Returns a human-readable validation error mapped to ErrBadRequest.
func DecodeValidate[T any](body io.Reader, dst *T) error {
	if err := json.NewDecoder(body).Decode(dst); err != nil {
		return fmt.Errorf("%w: invalid request body", apierr.ErrBadRequest)
	}

	if err := validate.Struct(dst); err != nil {
		var msgs string
		for _, validationErr := range err.(validator.ValidationErrors) {
			msgs = fmt.Sprintf("%s, %s", msgs, validationErr.Field()+" is "+validationErr.Tag())
		}
		if msgs != "" {
			msgs = msgs[2:] // strip leading ", "
		}
		return fmt.Errorf("%w: %s", apierr.ErrBadRequest, msgs)
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

// RequireUserID extracts the authenticated user ID from the request context.
// Writes ErrUnauthorized and returns false if no user is present.
func RequireUserID(w http.ResponseWriter, r *http.Request) (string, bool) {
	userID, ok := UserIDFromContext(r.Context())
	if !ok {
		WriteError(w, apierr.ErrUnauthorized)
	}
	return userID, ok
}

// PathInt64 parses a path parameter as int64.
func PathInt64(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}

// QueryInt64 parses a query parameter as int64.
func QueryInt64(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.URL.Query().Get(key), 10, 64)
}

// Pagination extracts and clamps page/limit query parameters.
// Page defaults to 1 (minimum 1). Limit defaults to defaultLimit, clamped to [1, maxLimit].
func Pagination(r *http.Request, defaultLimit, maxLimit int) (page, limit int) {
	page = QueryInt(r, "page", 1)
	if page < 1 {
		page = 1
	}
	limit = QueryInt(r, "limit", defaultLimit)
	if limit < 1 || limit > maxLimit {
		limit = defaultLimit
	}
	return page, limit
}

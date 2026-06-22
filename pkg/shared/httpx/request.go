package httpx

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/go-playground/validator/v10"
	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

// DecodeJSON decodes the request body into v, returning a wrapped ErrBadRequest on failure.
func DecodeJSON(r *http.Request, v any) error {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		return fmt.Errorf("%w: invalid request body", apierr.ErrBadRequest)
	}
	return nil
}

// DecodeValidate decodes a JSON body and validates the struct using go-playground/validator.
// Returns a human-readable validation error mapped to ErrBadRequest.
func DecodeValidate[T any](body io.Reader, dst *T) error {
	if err := json.NewDecoder(body).Decode(dst); err != nil {
		return fmt.Errorf("%w: invalid request body", apierr.ErrBadRequest)
	}

	validate := validator.New()
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

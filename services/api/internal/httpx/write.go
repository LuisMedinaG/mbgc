package httpx

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
)

// WriteJSON serializes v as JSON with the given HTTP status code.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("failed to encode JSON response", "error", err)
	}
}

// WriteError maps a sentinel error to the correct HTTP status and error envelope.
// Unknown errors become 500 and are logged server-side — internal details are never leaked.
func WriteError(w http.ResponseWriter, err error) {
	var status int
	var code, msg string

	switch {
	case errors.Is(err, apierr.ErrNotFound):
		status, code, msg = http.StatusNotFound, apierr.CodeNotFound, err.Error()
	case errors.Is(err, apierr.ErrDuplicate):
		status, code, msg = http.StatusConflict, apierr.CodeDuplicate, err.Error()
	case errors.Is(err, apierr.ErrUnauthorized), errors.Is(err, apierr.ErrWrongPassword):
		status, code, msg = http.StatusUnauthorized, apierr.CodeUnauthorized, "unauthorized"
	case errors.Is(err, apierr.ErrForbidden):
		status, code, msg = http.StatusForbidden, apierr.CodeForbidden, "forbidden"
	case errors.Is(err, apierr.ErrRateLimit):
		status, code, msg = http.StatusTooManyRequests, apierr.CodeRateLimit, err.Error()
	case errors.Is(err, apierr.ErrBadRequest):
		status, code, msg = http.StatusBadRequest, apierr.CodeBadRequest, err.Error()
	case errors.Is(err, apierr.ErrUnsupportedMediaType):
		status, code, msg = http.StatusUnsupportedMediaType, apierr.CodeUnsupportedMediaType, err.Error()
	case errors.Is(err, apierr.ErrValidation):
		status, code, msg = http.StatusUnprocessableEntity, apierr.CodeValidation, err.Error()
	default:
		slog.Error("unhandled error", "error", err)
		status, code, msg = http.StatusInternalServerError, apierr.CodeInternal, "internal server error"
	}

	WriteJSON(w, status, NewError(code, msg))
}

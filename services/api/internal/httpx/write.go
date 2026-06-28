package httpx

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
)

// WriteJSON serializes the provided value 'v' as JSON and writes it to the response
// with the specified HTTP status code. It also sets the Content-Type header to
// application/json; charset=utf-8.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("failed to encode JSON response", "error", err)
	}
}

// WriteError maps a sentinel error from the apierr package to its corresponding
// HTTP status code and returns a standardized JSON error envelope.
//
// Key behaviors:
//   - Sentinel errors (like apierr.ErrNotFound) map to specific status codes (404).
//   - Unknown errors default to 500 Internal Server Error.
//   - Internal implementation details are NEVER leaked to the client; only safe
//     messages and machine-readable codes are returned.
//   - All errors are logged server-side for debugging.
func WriteError(w http.ResponseWriter, err error) {
	var status int
	var code, msg string

	switch {
	case errors.Is(err, apierr.ErrNotFound):
		status, code, msg = http.StatusNotFound, apierr.CodeNotFound, apierr.ErrNotFound.Error()
	case errors.Is(err, apierr.ErrDuplicate):
		status, code, msg = http.StatusConflict, apierr.CodeDuplicate, apierr.ErrDuplicate.Error()
	case errors.Is(err, apierr.ErrUnauthorized), errors.Is(err, apierr.ErrWrongPassword):
		status, code, msg = http.StatusUnauthorized, apierr.CodeUnauthorized, "unauthorized"
	case errors.Is(err, apierr.ErrForbidden):
		status, code, msg = http.StatusForbidden, apierr.CodeForbidden, "forbidden"
	case errors.Is(err, apierr.ErrRateLimit):
		status, code, msg = http.StatusTooManyRequests, apierr.CodeRateLimit, apierr.ErrRateLimit.Error()
	case errors.Is(err, apierr.ErrBadRequest):
		status, code, msg = http.StatusBadRequest, apierr.CodeBadRequest, apierr.ErrBadRequest.Error()
	case errors.Is(err, apierr.ErrUnsupportedMediaType):
		status, code, msg = http.StatusUnsupportedMediaType, apierr.CodeUnsupportedMediaType, apierr.ErrUnsupportedMediaType.Error()
	case errors.Is(err, apierr.ErrValidation):
		status, code, msg = http.StatusUnprocessableEntity, apierr.CodeValidation, apierr.ErrValidation.Error()
	default:
		slog.Error("unhandled error", "error", err)
		status, code, msg = http.StatusInternalServerError, apierr.CodeInternal, "internal server error"
	}

	if status < 500 {
		slog.Error("request error", "error", err, "status", status, "code", code)
	}

	WriteJSON(w, status, NewError(code, msg))
}

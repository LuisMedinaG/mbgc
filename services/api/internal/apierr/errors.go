// Package apierr defines sentinel errors and machine-readable error codes
// shared across all mbgc services.
//
// The service layer returns sentinel errors (e.g. ErrNotFound).
// HTTP handlers call httpx.WriteError which maps them to status codes + error envelopes.
package apierr

import "errors"

// Machine-readable error codes returned in ErrorResponse.Error.Code.
// Keep these stable — clients may switch on them.
const (
	CodeBadRequest           = "BAD_REQUEST"
	CodeConflict             = "CONFLICT"
	CodeDuplicate            = "DUPLICATE"
	CodeForbidden            = "FORBIDDEN"
	CodeInternal             = "INTERNAL_ERROR"
	CodeNotFound             = "NOT_FOUND"
	CodeRateLimit            = "RATE_LIMIT_EXCEEDED"
	CodeUnauthorized         = "UNAUTHORIZED"
	CodeUnsupportedMediaType = "UNSUPPORTED_MEDIA_TYPE"
	CodeValidation           = "VALIDATION_FAILED"
)

// Sentinel errors returned by the service layer.
// Use errors.Is for comparison; wrap with fmt.Errorf("%w", ...) to add context.
var (
	ErrBadRequest           = errors.New("bad request")
	ErrDuplicate            = errors.New("duplicate")
	ErrForbidden            = errors.New("forbidden")
	ErrInternal             = errors.New("internal error")
	ErrNotFound             = errors.New("not found")
	ErrRateLimit            = errors.New("rate limit exceeded")
	ErrUnauthorized         = errors.New("unauthorized")
	ErrUnsupportedMediaType = errors.New("unsupported media type")
	ErrValidation           = errors.New("validation failed")
	ErrWrongPassword        = errors.New("wrong password")
)

// Safe returns the sentinel error itself, stripping any wrapper text added via
// fmt.Errorf("%w: detail", ...). This ensures client-facing error messages never
// expose internal details. The original err is logged server-side for debugging.
func Safe(err error) error {
	switch {
	case errors.Is(err, ErrBadRequest):
		return ErrBadRequest
	case errors.Is(err, ErrDuplicate):
		return ErrDuplicate
	case errors.Is(err, ErrForbidden):
		return ErrForbidden
	case errors.Is(err, ErrInternal):
		return ErrInternal
	case errors.Is(err, ErrNotFound):
		return ErrNotFound
	case errors.Is(err, ErrRateLimit):
		return ErrRateLimit
	case errors.Is(err, ErrUnauthorized), errors.Is(err, ErrWrongPassword):
		return ErrUnauthorized
	case errors.Is(err, ErrUnsupportedMediaType):
		return ErrUnsupportedMediaType
	case errors.Is(err, ErrValidation):
		return ErrValidation
	default:
		return ErrInternal
	}
}

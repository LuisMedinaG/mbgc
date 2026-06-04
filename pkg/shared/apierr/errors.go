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
	CodeBadRequest   = "BAD_REQUEST"
	CodeConflict     = "CONFLICT"
	CodeDuplicate    = "DUPLICATE"
	CodeForbidden    = "FORBIDDEN"
	CodeInternal     = "INTERNAL_ERROR"
	CodeNotFound     = "NOT_FOUND"
	CodeRateLimit    = "RATE_LIMIT_EXCEEDED"
	CodeUnauthorized = "UNAUTHORIZED"
	CodeValidation   = "VALIDATION_FAILED"
)

// Sentinel errors returned by the service layer.
// Use errors.Is for comparison; wrap with fmt.Errorf("%w", ...) to add context.
// ref: api-layer.APIERR.1 — defines sentinel errors for all HTTP categories
// ref: api-layer.APIERR.2 — each sentinel is a unique value identifiable via errors.Is
// ref: api-layer.APIERR.3 — provides Is* helper functions
// ref: api-layer.APIERR.4 — each wraps a machine-readable code
var (
	ErrBadRequest    = errors.New("bad request")
	ErrDuplicate     = errors.New("duplicate")
	ErrForbidden     = errors.New("forbidden")
	ErrInternal      = errors.New("internal error")
	ErrNotFound      = errors.New("not found")
	ErrRateLimit     = errors.New("rate limit exceeded")
	ErrUnauthorized  = errors.New("unauthorized")
	ErrValidation    = errors.New("validation failed")
	ErrWrongPassword = errors.New("wrong password")
)

func IsBadRequest(err error) bool  { return errors.Is(err, ErrBadRequest) }
func IsDuplicate(err error) bool   { return errors.Is(err, ErrDuplicate) }
func IsForbidden(err error) bool   { return errors.Is(err, ErrForbidden) }
func IsNotFound(err error) bool    { return errors.Is(err, ErrNotFound) }
func IsRateLimit(err error) bool   { return errors.Is(err, ErrRateLimit) }
func IsValidation(err error) bool  { return errors.Is(err, ErrValidation) }

// IsUnauthorized reports whether err is or wraps ErrUnauthorized or ErrWrongPassword.
func IsUnauthorized(err error) bool {
	return errors.Is(err, ErrUnauthorized) || errors.Is(err, ErrWrongPassword)
}

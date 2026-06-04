// Package envelope provides standard JSON response wrappers for all mbgc services.
//
// Every handler should return one of:
//
//	 envelope.Response[T]      — single resource
//	 envelope.ListResponse[T]  — paginated collection
//	 envelope.ErrorResponse    — error condition
//
// Wire format:
//
//	{"data": {...}}
//	{"data": [...], "meta": {"page": 1, "limit": 20, "total": 142}}
//	{"error": {"code": "NOT_FOUND", "message": "game not found"}}
package envelope

// Response wraps a single resource.
// ref: api-layer.ENVELOPE.1 — single-item response with data field
type Response[T any] struct {
	Data T `json:"data"`
}

// ListResponse wraps a paginated collection.
// ref: api-layer.ENVELOPE.2 — paginated list with page/limit/total metadata
type ListResponse[T any] struct {
	Data []T  `json:"data"`
	Meta Meta `json:"meta"`
}

// Meta holds pagination metadata.
type Meta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}

// ErrorResponse is returned for all error conditions.
// ref: api-layer.ENVELOPE.3 — error response with code, message, optional details
type ErrorResponse struct {
	Error APIError `json:"error"`
}

// APIError carries a machine-readable code and a human-readable message.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
}

// New wraps a single resource in a Response.
// ref: api-layer.ENVELOPE.4 — New/NewList/NewError constructors
func New[T any](data T) Response[T] {
	return Response[T]{Data: data}
}

// NewList wraps a paginated collection.
// If data is nil it is coerced to an empty slice so the wire format is always [].
func NewList[T any](data []T, page, limit, total int) ListResponse[T] {
	if data == nil {
		data = []T{}
	}
	return ListResponse[T]{
		Data: data,
		Meta: Meta{Page: page, Limit: limit, Total: total},
	}
}

// NewError builds an ErrorResponse.
// Pass an optional details value (e.g. map[string]string of field errors) as the third argument.
func NewError(code, message string, details ...any) ErrorResponse {
	e := ErrorResponse{Error: APIError{Code: code, Message: message}}
	if len(details) > 0 && details[0] != nil {
		e.Error.Details = details[0]
	}
	return e
}

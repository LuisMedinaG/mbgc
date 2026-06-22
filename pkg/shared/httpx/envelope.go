package httpx

// Response wraps a single item in the standard API envelope.
type Response[T any] struct {
	Data T `json:"data"`
}

// ListResponse wraps a paginated list in the standard API envelope.
type ListResponse[T any] struct {
	Data []T      `json:"data"`
	Meta PageMeta `json:"meta"`
}

// PageMeta holds pagination metadata.
type PageMeta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}

// ErrorResponse is the standard API error envelope.
type ErrorResponse struct {
	Error APIError `json:"error"`
}

// APIError carries the machine-readable code and human-readable message.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
}

// New wraps data in a single-item envelope.
func New[T any](data T) Response[T] {
	return Response[T]{Data: data}
}

// NewList wraps a slice in a paginated envelope. A nil slice is coerced to []T{}
// so the JSON field is always an array, never null.
func NewList[T any](data []T, page, limit, total int) ListResponse[T] {
	if data == nil {
		data = []T{}
	}
	return ListResponse[T]{
		Data: data,
		Meta: PageMeta{Page: page, Limit: limit, Total: total},
	}
}

// NewError builds an error envelope from a code and message.
func NewError(code, message string, details ...any) ErrorResponse {
	e := ErrorResponse{Error: APIError{Code: code, Message: message}}
	if len(details) > 0 && details[0] != nil {
		e.Error.Details = details[0]
	}
	return e
}

package response

import (
	"encoding/json"
	"net/http"
)

func JSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func OK(w http.ResponseWriter, data any) {
	JSON(w, http.StatusOK, map[string]any{"data": data})
}

func Created(w http.ResponseWriter, data any) {
	JSON(w, http.StatusCreated, map[string]any{"data": data})
}

func Error(w http.ResponseWriter, status int, message string) {
	JSON(w, status, map[string]any{"error": message})
}

func BadRequest(w http.ResponseWriter, message string) {
	Error(w, http.StatusBadRequest, message)
}

func Unauthorized(w http.ResponseWriter) {
	Error(w, http.StatusUnauthorized, "unauthorized")
}

func Forbidden(w http.ResponseWriter) {
	Error(w, http.StatusForbidden, "forbidden")
}

func NotFound(w http.ResponseWriter) {
	Error(w, http.StatusNotFound, "not found")
}

func InternalError(w http.ResponseWriter) {
	Error(w, http.StatusInternalServerError, "internal server error")
}

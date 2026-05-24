package httpx_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

func TestWriteJSON(t *testing.T) {
	w := httptest.NewRecorder()
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"hello": "world"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if ct := w.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Fatalf("Content-Type = %q", ct)
	}
}

func TestWriteError(t *testing.T) {
	tests := []struct {
		err        error
		wantStatus int
		wantCode   string
	}{
		{apierr.ErrNotFound, http.StatusNotFound, apierr.CodeNotFound},
		{apierr.ErrDuplicate, http.StatusConflict, apierr.CodeDuplicate},
		{apierr.ErrUnauthorized, http.StatusUnauthorized, apierr.CodeUnauthorized},
		{apierr.ErrWrongPassword, http.StatusUnauthorized, apierr.CodeUnauthorized},
		{apierr.ErrForbidden, http.StatusForbidden, apierr.CodeForbidden},
		{apierr.ErrRateLimit, http.StatusTooManyRequests, apierr.CodeRateLimit},
		{apierr.ErrBadRequest, http.StatusBadRequest, apierr.CodeBadRequest},
		{apierr.ErrValidation, http.StatusUnprocessableEntity, apierr.CodeValidation},
		{fmt.Errorf("boom"), http.StatusInternalServerError, apierr.CodeInternal},
	}

	for _, tt := range tests {
		t.Run(tt.wantCode, func(t *testing.T) {
			w := httptest.NewRecorder()
			httpx.WriteError(w, tt.err)
			if w.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d", w.Code, tt.wantStatus)
			}
			var resp envelope.ErrorResponse
			if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
				t.Fatalf("decode: %v", err)
			}
			if resp.Error.Code != tt.wantCode {
				t.Errorf("code = %q, want %q", resp.Error.Code, tt.wantCode)
			}
		})
	}
}

func TestWriteError_Wrapped(t *testing.T) {
	err := fmt.Errorf("game 42: %w", apierr.ErrNotFound)
	w := httptest.NewRecorder()
	httpx.WriteError(w, err)
	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404", w.Code)
	}
}

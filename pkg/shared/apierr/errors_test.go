package apierr_test

import (
	"fmt"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

func TestHelpers(t *testing.T) {
	tests := []struct {
		sentinel error
		fn       func(error) bool
		name     string
	}{
		{apierr.ErrBadRequest, apierr.IsBadRequest, "IsBadRequest"},
		{apierr.ErrDuplicate, apierr.IsDuplicate, "IsDuplicate"},
		{apierr.ErrForbidden, apierr.IsForbidden, "IsForbidden"},
		{apierr.ErrNotFound, apierr.IsNotFound, "IsNotFound"},
		{apierr.ErrRateLimit, apierr.IsRateLimit, "IsRateLimit"},
		{apierr.ErrValidation, apierr.IsValidation, "IsValidation"},
		{apierr.ErrUnauthorized, apierr.IsUnauthorized, "IsUnauthorized"},
		{apierr.ErrWrongPassword, apierr.IsUnauthorized, "IsUnauthorized(WrongPassword)"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if !tt.fn(tt.sentinel) {
				t.Errorf("%s(sentinel) = false, want true", tt.name)
			}
			wrapped := fmt.Errorf("context: %w", tt.sentinel)
			if !tt.fn(wrapped) {
				t.Errorf("%s(wrapped) = false, want true", tt.name)
			}
			if tt.fn(apierr.ErrInternal) {
				t.Errorf("%s(unrelated) = true, want false", tt.name)
			}
		})
	}
}

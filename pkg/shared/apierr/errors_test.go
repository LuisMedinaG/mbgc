package apierr_test

import (
	"errors"
	"fmt"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

func TestSentinels(t *testing.T) {
	sentinels := []struct {
		err  error
		name string
	}{
		{apierr.ErrBadRequest, "ErrBadRequest"},
		{apierr.ErrDuplicate, "ErrDuplicate"},
		{apierr.ErrForbidden, "ErrForbidden"},
		{apierr.ErrNotFound, "ErrNotFound"},
		{apierr.ErrRateLimit, "ErrRateLimit"},
		{apierr.ErrValidation, "ErrValidation"},
		{apierr.ErrUnauthorized, "ErrUnauthorized"},
		{apierr.ErrWrongPassword, "ErrWrongPassword"},
		{apierr.ErrInternal, "ErrInternal"},
		{apierr.ErrUnsupportedMediaType, "ErrUnsupportedMediaType"},
	}

	for _, tt := range sentinels {
		t.Run(tt.name, func(t *testing.T) {
			if !errors.Is(tt.err, tt.err) {
				t.Errorf("%s does not match itself", tt.name)
			}
			wrapped := fmt.Errorf("context: %w", tt.err)
			if !errors.Is(wrapped, tt.err) {
				t.Errorf("wrapped %s not matched by errors.Is", tt.name)
			}
		})
	}
}

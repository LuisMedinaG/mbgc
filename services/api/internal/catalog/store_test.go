package catalog

import (
	"errors"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

// ref: game-detail.RULES_URL.1 — server-side allowlist must reject javascript: URIs
// and any non-Drive/Docs host before persistence.
func TestValidateRulesURL(t *testing.T) {
	cases := []struct {
		name    string
		url     string
		wantErr bool
	}{
		{"empty clears", "", false},
		{"drive https", "https://drive.google.com/file/d/abc", false},
		{"docs https", "https://docs.google.com/document/d/abc/edit", false},
		{"javascript scheme", "javascript:alert(1)", true},
		{"data scheme", "data:text/html,<script>alert(1)</script>", true},
		{"vbscript scheme", "vbscript:msgbox(1)", true},
		{"http (not https)", "http://drive.google.com/x", true},
		{"unrelated host", "https://evil.com/x", true},
		{"relative path", "/local/file.pdf", true},
		{"drive subdomain abuse", "https://drive.google.com.evil.com/x", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateRulesURL(tc.url)
			if tc.wantErr {
				if !errors.Is(err, apierr.ErrValidation) {
					t.Fatalf("expected ErrValidation, got %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("expected nil, got %v", err)
			}
		})
	}
}

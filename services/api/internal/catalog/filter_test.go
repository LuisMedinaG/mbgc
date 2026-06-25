package catalog

import (
	"context"
	"io"
	"strings"
	"testing"

	sq "github.com/Masterminds/squirrel"
)

func TestGamePredicates_PlayerFilter(t *testing.T) {
	tests := []struct {
		filterValue string
		wantSQL     []string
	}{
		{"1", []string{"min_players <= ?", "max_players >= ?"}},
		{"2", []string{"min_players <= ?", "max_players >= ?"}},
		{"2only", []string{"min_players = ?", "max_players = ?"}},
		{"3", []string{"min_players <= ?", "max_players >= ?"}},
		{"4", []string{"min_players <= ?", "max_players >= ?"}},
		{"5plus", []string{"max_players >= ?"}},
	}

	for _, tt := range tests {
		t.Run("Players_"+tt.filterValue, func(t *testing.T) {
			f := GameFilter{Players: tt.filterValue}
			pred := gamePredicates("user-1", f)

			sql, _, err := sq.Select("*").From("games").Where(pred).ToSql()
			if err != nil {
				t.Fatalf("ToSql: %v", err)
			}

			if !strings.Contains(sql, "user_id = ?") {
				t.Errorf("expected user_id predicate, got %s", sql)
			}

			for _, want := range tt.wantSQL {
				if !strings.Contains(sql, want) {
					t.Errorf("filter %s: expected SQL to contain %s, got %s", tt.filterValue, want, sql)
				}
			}
		})
	}
}

type mockStorage struct {
	uploadFn func(ctx context.Context, bucket, filename string, content io.Reader, contentType string) error
	removeFn func(ctx context.Context, bucket, filename string) error
}

func (m *mockStorage) Upload(ctx context.Context, bucket, filename string, content io.Reader, contentType string) error {
	return m.uploadFn(ctx, bucket, filename, content, contentType)
}

func (m *mockStorage) Remove(ctx context.Context, bucket, filename string) error {
	return m.removeFn(ctx, bucket, filename)
}

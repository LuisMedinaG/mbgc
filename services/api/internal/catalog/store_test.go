package catalog

import (
	"context"
	"errors"
	"testing"

	"github.com/LuisMedinaG/mbgc/services/api/internal/apierr"
	"github.com/LuisMedinaG/mbgc/services/api/internal/testutil"
	"github.com/google/uuid"
)

// newTestStore returns a Store backed by a migrated DATABASE_URL and a fresh
// per-test user ID (no FK to auth.users, so any UUID is valid). Skips if
// DATABASE_URL is unset.
func newTestStore(t *testing.T) (*Store, string) {
	t.Helper()
	pool := testutil.NewTestDB(t)
	return NewStore(pool), uuid.NewString()
}

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

func TestStore_CreateAndGetGame(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	id, err := s.CreateGame(ctx, userID, 12345)
	if err != nil {
		t.Fatalf("CreateGame: %v", err)
	}

	g, err := s.GetGame(ctx, id, userID)
	if err != nil {
		t.Fatalf("GetGame: %v", err)
	}
	if g.BGGID == nil || *g.BGGID != 12345 {
		t.Fatalf("expected bgg_id 12345, got %v", g.BGGID)
	}

	if _, err := s.GetGame(ctx, id, uuid.NewString()); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound for wrong user, got %v", err)
	}
}

func TestStore_GameExistsByBGGID(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	if exists, err := s.GameExistsByBGGID(ctx, userID, 999); err != nil || exists {
		t.Fatalf("expected (false, nil) before insert, got (%v, %v)", exists, err)
	}

	if _, err := s.CreateGame(ctx, userID, 999); err != nil {
		t.Fatalf("CreateGame: %v", err)
	}

	if exists, err := s.GameExistsByBGGID(ctx, userID, 999); err != nil || !exists {
		t.Fatalf("expected (true, nil) after insert, got (%v, %v)", exists, err)
	}
}

func TestStore_UpsertBGGGame(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	data := BGGGameData{BGGID: 42, Name: "Catan"}
	id, created, err := s.UpsertBGGGame(ctx, userID, data)
	if err != nil {
		t.Fatalf("UpsertBGGGame insert: %v", err)
	}
	if !created {
		t.Fatal("expected created=true on first upsert")
	}

	data.Name = "Catan (Updated)"
	id2, created2, err := s.UpsertBGGGame(ctx, userID, data)
	if err != nil {
		t.Fatalf("UpsertBGGGame update: %v", err)
	}
	if created2 {
		t.Fatal("expected created=false on conflict update")
	}
	if id != id2 {
		t.Fatalf("expected same id on conflict, got %d and %d", id, id2)
	}

	g, err := s.GetGame(ctx, id, userID)
	if err != nil {
		t.Fatalf("GetGame: %v", err)
	}
	if g.Name != "Catan (Updated)" {
		t.Fatalf("expected updated name, got %q", g.Name)
	}
}

func TestStore_UpsertBGGGame_BlankNameFallback(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	id, _, err := s.UpsertBGGGame(ctx, userID, BGGGameData{BGGID: 7})
	if err != nil {
		t.Fatalf("UpsertBGGGame: %v", err)
	}
	g, err := s.GetGame(ctx, id, userID)
	if err != nil {
		t.Fatalf("GetGame: %v", err)
	}
	if g.Name != "(unnamed BGG 7)" {
		t.Fatalf("expected fallback name, got %q", g.Name)
	}
}

func TestStore_DeleteGame(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	id, err := s.CreateGame(ctx, userID, 1)
	if err != nil {
		t.Fatalf("CreateGame: %v", err)
	}

	if err := s.DeleteGame(ctx, id, uuid.NewString()); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound deleting as wrong user, got %v", err)
	}

	if err := s.DeleteGame(ctx, id, userID); err != nil {
		t.Fatalf("DeleteGame: %v", err)
	}

	if _, err := s.GetGame(ctx, id, userID); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestStore_ListGames(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	if _, _, err := s.UpsertBGGGame(ctx, userID, BGGGameData{BGGID: 1, Name: "Wingspan", PlayTime: intPtr(60)}); err != nil {
		t.Fatalf("UpsertBGGGame: %v", err)
	}
	if _, _, err := s.UpsertBGGGame(ctx, userID, BGGGameData{BGGID: 2, Name: "Azul", PlayTime: intPtr(30)}); err != nil {
		t.Fatalf("UpsertBGGGame: %v", err)
	}

	games, total, err := s.ListGames(ctx, userID, GameFilter{Page: 1, Limit: 10})
	if err != nil {
		t.Fatalf("ListGames: %v", err)
	}
	if total != 2 || len(games) != 2 {
		t.Fatalf("expected 2 games, got total=%d len=%d", total, len(games))
	}

	games, total, err = s.ListGames(ctx, userID, GameFilter{Page: 1, Limit: 10, Search: "Wingspan"})
	if err != nil {
		t.Fatalf("ListGames search: %v", err)
	}
	if total != 1 || len(games) != 1 || games[0].Name != "Wingspan" {
		t.Fatalf("expected 1 match for Wingspan, got total=%d games=%+v", total, games)
	}
}

func TestStore_CollectionsCRUD(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	c, err := s.CreateCollection(ctx, userID, "Party Games", "fun stuff")
	if err != nil {
		t.Fatalf("CreateCollection: %v", err)
	}

	cols, err := s.ListCollections(ctx, userID)
	if err != nil {
		t.Fatalf("ListCollections: %v", err)
	}
	if len(cols) != 1 || cols[0].Name != "Party Games" {
		t.Fatalf("expected 1 collection named Party Games, got %+v", cols)
	}

	if err := s.UpdateCollection(ctx, c.ID, userID, "Party Games!", "updated"); err != nil {
		t.Fatalf("UpdateCollection: %v", err)
	}
	if err := s.UpdateCollection(ctx, c.ID, uuid.NewString(), "x", "y"); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound updating as wrong user, got %v", err)
	}

	if err := s.DeleteCollection(ctx, c.ID, uuid.NewString()); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound deleting as wrong user, got %v", err)
	}
	if err := s.DeleteCollection(ctx, c.ID, userID); err != nil {
		t.Fatalf("DeleteCollection: %v", err)
	}
}

func TestStore_SetGameCollectionsAndDiscover(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	gameID, _, err := s.UpsertBGGGame(ctx, userID, BGGGameData{BGGID: 1, Name: "Wingspan", Categories: []string{"Birds"}})
	if err != nil {
		t.Fatalf("UpsertBGGGame: %v", err)
	}
	col, err := s.CreateCollection(ctx, userID, "Favorites", "")
	if err != nil {
		t.Fatalf("CreateCollection: %v", err)
	}

	if err := s.SetGameCollections(ctx, userID, gameID, []int64{col.ID}); err != nil {
		t.Fatalf("SetGameCollections: %v", err)
	}

	if err := s.SetGameCollections(ctx, userID, gameID, []int64{9999999}); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound for unknown collection id, got %v", err)
	}

	games, total, gotCol, err := s.Discover(ctx, userID, DiscoverFilter{CollectionID: col.ID, Page: 1, Limit: 10})
	if err != nil {
		t.Fatalf("Discover: %v", err)
	}
	if total != 1 || len(games) != 1 || gotCol.ID != col.ID {
		t.Fatalf("expected 1 game in collection, got total=%d games=%+v", total, games)
	}

	if _, _, _, err := s.Discover(ctx, userID, DiscoverFilter{CollectionID: 9999999, Page: 1, Limit: 10}); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound for unknown collection, got %v", err)
	}
}

func TestStore_UpdateRulesURL(t *testing.T) {
	s, userID := newTestStore(t)
	ctx := context.Background()

	id, err := s.CreateGame(ctx, userID, 1)
	if err != nil {
		t.Fatalf("CreateGame: %v", err)
	}

	if err := s.UpdateRulesURL(ctx, id, userID, "javascript:alert(1)"); !errors.Is(err, apierr.ErrValidation) {
		t.Fatalf("expected ErrValidation, got %v", err)
	}

	if err := s.UpdateRulesURL(ctx, id, userID, "https://drive.google.com/file/d/abc"); err != nil {
		t.Fatalf("UpdateRulesURL: %v", err)
	}
	g, err := s.GetGame(ctx, id, userID)
	if err != nil {
		t.Fatalf("GetGame: %v", err)
	}
	if g.RulesURL == nil || *g.RulesURL != "https://drive.google.com/file/d/abc" {
		t.Fatalf("expected rules_url set, got %v", g.RulesURL)
	}

	if err := s.UpdateRulesURL(ctx, id, uuid.NewString(), "https://drive.google.com/file/d/abc"); !errors.Is(err, apierr.ErrNotFound) {
		t.Fatalf("expected ErrNotFound updating as wrong user, got %v", err)
	}
}

func TestGamePredicates(t *testing.T) {
	cases := []struct {
		name string
		f    GameFilter
	}{
		{"no filters", GameFilter{}},
		{"search", GameFilter{Search: "catan"}},
		{"category", GameFilter{Category: "Strategy"}},
		{"players 1", GameFilter{Players: "1"}},
		{"players 2only", GameFilter{Players: "2only"}},
		{"players 5plus", GameFilter{Players: "5plus"}},
		{"playtime short", GameFilter{Playtime: "short"}},
		{"playtime medium", GameFilter{Playtime: "medium"}},
		{"playtime long", GameFilter{Playtime: "long"}},
		{"weight light", GameFilter{Weight: "light"}},
		{"weight medium", GameFilter{Weight: "medium"}},
		{"weight heavy", GameFilter{Weight: "heavy"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pred := gamePredicates("user-1", tc.f)
			if len(pred) == 0 {
				t.Fatal("expected at least the user_id predicate")
			}
		})
	}
}

func TestEmptySliceHelpers(t *testing.T) {
	if got := emptySlice(nil); got == nil || len(got) != 0 {
		t.Fatalf("emptySlice(nil) = %v, want empty non-nil slice", got)
	}
	if got := emptySlice([]string{"a"}); len(got) != 1 {
		t.Fatalf("emptySlice passthrough failed: %v", got)
	}
	if got := emptyIntSlice(nil); got == nil || len(got) != 0 {
		t.Fatalf("emptyIntSlice(nil) = %v, want empty non-nil slice", got)
	}
	if got := nullStr(""); got != nil {
		t.Fatalf("nullStr(\"\") = %v, want nil", got)
	}
	if got := nullStr("x"); got != "x" {
		t.Fatalf("nullStr(\"x\") = %v, want \"x\"", got)
	}
}

func intPtr(i int) *int { return &i }

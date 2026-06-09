package game

import (
	"context"
	"errors"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
)

// ref: importer.GAME_CREATION — pure-method coverage for the helpers the
// importer package depends on (CreateGame, GameExistsByBGGID, UpsertBGGGame,
// Discover). These all just delegate to the store, so the tests are thin.

func TestService_CreateGame_DelegatesToStore(t *testing.T) {
	want := int64(42)
	s := NewService(&mockGameStore{
		createGameFn: func(_ context.Context, userID string, bggID int) (int64, error) {
			if userID != "u1" || bggID != 174430 {
				t.Errorf("unexpected args: userID=%q bggID=%d", userID, bggID)
			}
			return want, nil
		},
	})
	got, err := s.CreateGame(context.Background(), "u1", 174430)
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if got != want {
		t.Errorf("CreateGame = %d, want %d", got, want)
	}
}

func TestService_CreateGame_PropagatesError(t *testing.T) {
	s := NewService(&mockGameStore{
		createGameFn: func(_ context.Context, _ string, _ int) (int64, error) {
			return 0, apierr.ErrInternal
		},
	})
	if _, err := s.CreateGame(context.Background(), "u1", 1); !errors.Is(err, apierr.ErrInternal) {
		t.Errorf("expected ErrInternal, got %v", err)
	}
}

func TestService_GameExistsByBGGID_Delegates(t *testing.T) {
	s := NewService(&mockGameStore{
		gameExistsByBGGIDFn: func(_ context.Context, userID string, bggID int) (bool, error) {
			return bggID == 13, nil
		},
	})
	exists, err := s.GameExistsByBGGID(context.Background(), "u1", 13)
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if !exists {
		t.Error("expected exists=true for bggID 13")
	}
	exists, _ = s.GameExistsByBGGID(context.Background(), "u1", 99)
	if exists {
		t.Error("expected exists=false for bggID 99")
	}
}

func TestService_UpsertBGGGame_Delegates(t *testing.T) {
	s := NewService(&mockGameStore{
		upsertBGGGameFn: func(_ context.Context, userID string, g BGGGameData) (int64, bool, error) {
			if g.BGGID != 174430 || g.Name != "Gloomhaven" {
				t.Errorf("unexpected payload: %+v", g)
			}
			return 7, true, nil
		},
	})
	id, created, err := s.UpsertBGGGame(context.Background(), "u1", BGGGameData{BGGID: 174430, Name: "Gloomhaven"})
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if id != 7 || !created {
		t.Errorf("UpsertBGGGame = (%d, %v), want (7, true)", id, created)
	}
}

func TestService_Discover_Delegates(t *testing.T) {
	wantCol := &Collection{ID: 5, Name: "Co-op"}
	s := NewService(&mockGameStore{
		discoverFn: func(_ context.Context, _ string, f DiscoverFilter) ([]Game, int, *Collection, error) {
			if f.CollectionID != 5 {
				t.Errorf("CollectionID = %d, want 5", f.CollectionID)
			}
			return []Game{{ID: 1, Name: "Pandemic"}}, 1, wantCol, nil
		},
	})
	games, total, col, err := s.Discover(context.Background(), "u1", DiscoverFilter{CollectionID: 5})
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if total != 1 || col != wantCol || len(games) != 1 {
		t.Errorf("Discover = %+v, %d, %+v, want 1 game + wantCol", games, total, col)
	}
}

// ref: game-detail.VIBE_ASSIGN.1 — SetGameCollections returns ErrNotFound
// when the game doesn't exist or doesn't belong to the user. The mock
// can simulate this to confirm the service propagates without wrapping.
func TestService_SetGameCollections_PropagatesNotFound(t *testing.T) {
	s := NewService(&mockGameStore{
		setGameCollectionsFn: func(_ context.Context, _ string, _ int64, _ []int64) error {
			return apierr.ErrNotFound
		},
	})
	if err := s.SetGameCollections(context.Background(), "u1", 99, []int64{1}); !errors.Is(err, apierr.ErrNotFound) {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

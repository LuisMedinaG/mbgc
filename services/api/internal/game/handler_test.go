package game

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// mockGameStore implements gameStore for handler tests.
type mockGameStore struct {
	listGamesFn          func(ctx context.Context, userID string, f GameFilter) ([]Game, int, error)
	getGameFn            func(ctx context.Context, id int64, userID string) (*Game, error)
	createGameFn         func(ctx context.Context, userID string, bggID int) (int64, error)
	gameExistsByBGGIDFn  func(ctx context.Context, userID string, bggID int) (bool, error)
	upsertBGGGameFn      func(ctx context.Context, userID string, g BGGGameData) (int64, bool, error)
	deleteGameFn         func(ctx context.Context, id int64, userID string) error
	listCollectionsFn    func(ctx context.Context, userID string) ([]Collection, error)
	createCollectionFn   func(ctx context.Context, userID, name, description string) (*Collection, error)
	updateCollectionFn   func(ctx context.Context, id int64, userID, name, description string) error
	deleteCollectionFn   func(ctx context.Context, id int64, userID string) error
	setGameCollectionsFn func(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error
	discoverFn           func(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error)
}

func (m *mockGameStore) ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
	return m.listGamesFn(ctx, userID, f)
}
func (m *mockGameStore) GetGame(ctx context.Context, id int64, userID string) (*Game, error) {
	return m.getGameFn(ctx, id, userID)
}
func (m *mockGameStore) CreateGame(ctx context.Context, userID string, bggID int) (int64, error) {
	return m.createGameFn(ctx, userID, bggID)
}
func (m *mockGameStore) GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error) {
	return m.gameExistsByBGGIDFn(ctx, userID, bggID)
}
func (m *mockGameStore) UpsertBGGGame(ctx context.Context, userID string, g BGGGameData) (int64, bool, error) {
	if m.upsertBGGGameFn != nil {
		return m.upsertBGGGameFn(ctx, userID, g)
	}
	return 0, true, nil
}
func (m *mockGameStore) DeleteGame(ctx context.Context, id int64, userID string) error {
	return m.deleteGameFn(ctx, id, userID)
}
func (m *mockGameStore) ListCollections(ctx context.Context, userID string) ([]Collection, error) {
	return m.listCollectionsFn(ctx, userID)
}
func (m *mockGameStore) CreateCollection(ctx context.Context, userID, name, description string) (*Collection, error) {
	return m.createCollectionFn(ctx, userID, name, description)
}
func (m *mockGameStore) UpdateCollection(ctx context.Context, id int64, userID, name, description string) error {
	return m.updateCollectionFn(ctx, id, userID, name, description)
}
func (m *mockGameStore) DeleteCollection(ctx context.Context, id int64, userID string) error {
	return m.deleteCollectionFn(ctx, id, userID)
}
func (m *mockGameStore) SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
	return m.setGameCollectionsFn(ctx, userID, gameID, collectionIDs)
}
func (m *mockGameStore) Discover(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error) {
	if m.discoverFn != nil {
		return m.discoverFn(ctx, userID, f)
	}
	return nil, 0, nil, apierr.ErrNotFound
}

func newAuthenticatedRequest(method, path string, body string) *http.Request {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "testuser", false)
	return r.WithContext(ctx)
}

func newUnauthenticatedRequest(method, path string) *http.Request {
	return httptest.NewRequest(method, path, nil)
}

// --- ListGames ---

func TestListGames_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("GET", "/api/v1/games")
	h.ListGames(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestListGames_Success(t *testing.T) {
	store := &mockGameStore{
		listGamesFn: func(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
			return []Game{{ID: 1, Name: "Catan"}}, 1, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/games?page=1&limit=20", "")
	h.ListGames(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.ListResponse[Game]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Data) != 1 || resp.Data[0].Name != "Catan" {
		t.Fatalf("unexpected body: %+v", resp)
	}
	if resp.Meta.Total != 1 {
		t.Fatalf("expected total=1, got %d", resp.Meta.Total)
	}
}

func TestListGames_StoreError(t *testing.T) {
	store := &mockGameStore{
		listGamesFn: func(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
			return nil, 0, apierr.ErrNotFound
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/games", "")
	h.ListGames(w, r)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// ref: collection.API.1 — page/limit must be clamped to safe bounds before hitting the store.
func TestListGames_ClampsPageAndLimit(t *testing.T) {
	var got GameFilter
	store := &mockGameStore{
		listGamesFn: func(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
			got = f
			return nil, 0, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/games?page=-5&limit=99999", "")
	h.ListGames(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if got.Page != 1 {
		t.Fatalf("expected page clamped to 1, got %d", got.Page)
	}
	if got.Limit != 20 {
		t.Fatalf("expected limit clamped to 20, got %d", got.Limit)
	}
}

// --- GetGame ---

func TestGetGame_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("GET", "/api/v1/games/1")
	h.GetGame(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestGetGame_InvalidID(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/games/abc", "")
	r.SetPathValue("id", "abc")
	h.GetGame(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestGetGame_Success(t *testing.T) {
	store := &mockGameStore{
		getGameFn: func(ctx context.Context, id int64, userID string) (*Game, error) {
			return &Game{ID: 1, Name: "Catan"}, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/games/1", "")
	r.SetPathValue("id", "1")
	h.GetGame(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.Response[Game]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Data.Name != "Catan" {
		t.Fatalf("expected Catan, got %s", resp.Data.Name)
	}
}

func TestGetGame_NotFound(t *testing.T) {
	store := &mockGameStore{
		getGameFn: func(ctx context.Context, id int64, userID string) (*Game, error) {
			return nil, apierr.ErrNotFound
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/games/1", "")
	r.SetPathValue("id", "1")
	h.GetGame(w, r)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// --- DeleteGame ---

func TestDeleteGame_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("DELETE", "/api/v1/games/1")
	h.DeleteGame(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestDeleteGame_Success(t *testing.T) {
	store := &mockGameStore{
		deleteGameFn: func(ctx context.Context, id int64, userID string) error {
			return nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("DELETE", "/api/v1/games/1", "")
	r.SetPathValue("id", "1")
	h.DeleteGame(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

func TestDeleteGame_NotFound(t *testing.T) {
	store := &mockGameStore{
		deleteGameFn: func(ctx context.Context, id int64, userID string) error {
			return apierr.ErrNotFound
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("DELETE", "/api/v1/games/1", "")
	r.SetPathValue("id", "1")
	h.DeleteGame(w, r)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// --- SetGameCollections ---

func TestSetGameCollections_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("POST", "/api/v1/games/1/collections")
	h.SetGameCollections(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestSetGameCollections_InvalidBody(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("POST", "/api/v1/games/1/collections", "not json")
	r.SetPathValue("id", "1")
	h.SetGameCollections(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestSetGameCollections_Success(t *testing.T) {
	store := &mockGameStore{
		setGameCollectionsFn: func(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
			return nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("POST", "/api/v1/games/1/collections", `{"collection_ids":[1,2]}`)
	r.SetPathValue("id", "1")
	h.SetGameCollections(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

func TestSetGameCollections_StoreError(t *testing.T) {
	store := &mockGameStore{
		setGameCollectionsFn: func(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
			return errors.New("db error")
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("POST", "/api/v1/games/1/collections", `{"collection_ids":[1]}`)
	r.SetPathValue("id", "1")
	h.SetGameCollections(w, r)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}

// --- ListCollections ---

func TestListCollections_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("GET", "/api/v1/collections")
	h.ListCollections(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestListCollections_Success(t *testing.T) {
	store := &mockGameStore{
		listCollectionsFn: func(ctx context.Context, userID string) ([]Collection, error) {
			return []Collection{{ID: 1, Name: "Favorites"}}, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/collections", "")
	h.ListCollections(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.ListResponse[Collection]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Data) != 1 || resp.Data[0].Name != "Favorites" {
		t.Fatalf("unexpected body: %+v", resp)
	}
}

// --- CreateCollection ---

func TestCreateCollection_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("POST", "/api/v1/collections")
	h.CreateCollection(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestCreateCollection_Success(t *testing.T) {
	store := &mockGameStore{
		createCollectionFn: func(ctx context.Context, userID, name, description string) (*Collection, error) {
			return &Collection{ID: 1, Name: name}, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("POST", "/api/v1/collections", `{"name":"Favorites","description":"top games"}`)
	h.CreateCollection(w, r)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", w.Code)
	}

	var resp envelope.Response[Collection]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Data.Name != "Favorites" {
		t.Fatalf("expected Favorites, got %s", resp.Data.Name)
	}
}

func TestCreateCollection_InvalidBody(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("POST", "/api/v1/collections", "bad json")
	h.CreateCollection(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// --- UpdateCollection ---

func TestUpdateCollection_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("PUT", "/api/v1/collections/1")
	h.UpdateCollection(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestUpdateCollection_Success(t *testing.T) {
	store := &mockGameStore{
		updateCollectionFn: func(ctx context.Context, id int64, userID, name, description string) error {
			return nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("PUT", "/api/v1/collections/1", `{"name":"Updated"}`)
	r.SetPathValue("id", "1")
	h.UpdateCollection(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

func TestUpdateCollection_NotFound(t *testing.T) {
	store := &mockGameStore{
		updateCollectionFn: func(ctx context.Context, id int64, userID, name, description string) error {
			return apierr.ErrNotFound
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("PUT", "/api/v1/collections/1", `{"name":"Updated"}`)
	r.SetPathValue("id", "1")
	h.UpdateCollection(w, r)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// --- DeleteCollection ---

func TestDeleteCollection_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockGameStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("DELETE", "/api/v1/collections/1")
	h.DeleteCollection(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestDeleteCollection_Success(t *testing.T) {
	store := &mockGameStore{
		deleteCollectionFn: func(ctx context.Context, id int64, userID string) error {
			return nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("DELETE", "/api/v1/collections/1", "")
	r.SetPathValue("id", "1")
	h.DeleteCollection(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

func TestDeleteCollection_NotFound(t *testing.T) {
	store := &mockGameStore{
		deleteCollectionFn: func(ctx context.Context, id int64, userID string) error {
			return apierr.ErrNotFound
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("DELETE", "/api/v1/collections/1", "")
	r.SetPathValue("id", "1")
	h.DeleteCollection(w, r)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// --- httpx.QueryInt ---

func TestQueryInt_Default(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	if v := httpx.QueryInt(r, "page", 1); v != 1 {
		t.Fatalf("expected 1, got %d", v)
	}
}

func TestQueryInt_Parsed(t *testing.T) {
	r := httptest.NewRequest("GET", "/?page=5", nil)
	if v := httpx.QueryInt(r, "page", 1); v != 5 {
		t.Fatalf("expected 5, got %d", v)
	}
}

func TestQueryInt_Invalid(t *testing.T) {
	r := httptest.NewRequest("GET", "/?page=abc", nil)
	if v := httpx.QueryInt(r, "page", 1); v != 1 {
		t.Fatalf("expected fallback 1, got %d", v)
	}
}

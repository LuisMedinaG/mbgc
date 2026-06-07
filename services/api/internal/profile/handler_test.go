package profile

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

// mockProfileStore implements profileStore for handler tests.
type mockProfileStore struct {
	getProfileFn    func(ctx context.Context, userID string) (*Profile, error)
	upsertProfileFn func(ctx context.Context, userID string) (*Profile, error)
	setBGGUsernameFn func(ctx context.Context, userID, bggUsername string) error
}

func (m *mockProfileStore) GetProfile(ctx context.Context, userID string) (*Profile, error) {
	return m.getProfileFn(ctx, userID)
}
func (m *mockProfileStore) UpsertProfile(ctx context.Context, userID string) (*Profile, error) {
	return m.upsertProfileFn(ctx, userID)
}
func (m *mockProfileStore) SetBGGUsername(ctx context.Context, userID, bggUsername string) error {
	return m.setBGGUsernameFn(ctx, userID, bggUsername)
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

// --- GetProfile ---

func TestGetProfile_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockProfileStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("GET", "/api/v1/profile")
	h.GetProfile(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

// ref: profile.VIEW.1 — GET /api/v1/profile returns profile in envelope
func TestGetProfile_Success(t *testing.T) {
	store := &mockProfileStore{
		getProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			return &Profile{ID: "user-1", BGGUsername: strPtr("bgghandle"), IsAdmin: false}, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/profile", "")
	h.GetProfile(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp envelope.Response[Profile]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Data.ID != "user-1" || *resp.Data.BGGUsername != "bgghandle" {
		t.Fatalf("unexpected body: %+v", resp)
	}
}

func TestGetProfile_LazyUpsert(t *testing.T) {
	calls := 0
	store := &mockProfileStore{
		getProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			calls++
			return nil, apierr.ErrNotFound
		},
		upsertProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			calls++
			return &Profile{ID: "user-1", IsAdmin: false}, nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/profile", "")
	h.GetProfile(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if calls != 2 {
		t.Fatalf("expected 2 store calls (get + upsert), got %d", calls)
	}
}

func TestGetProfile_StoreError(t *testing.T) {
	store := &mockProfileStore{
		getProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			return nil, apierr.ErrInternal
		},
		upsertProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			return nil, apierr.ErrInternal
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("GET", "/api/v1/profile", "")
	h.GetProfile(w, r)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}

// --- SetBGGUsername ---

// ref: profile.BGG_USERNAME.4 — scoped to authenticated user via JWT user_id
func TestSetBGGUsername_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&mockProfileStore{}))
	w := httptest.NewRecorder()
	r := newUnauthenticatedRequest("PUT", "/api/v1/profile/bgg-username")
	h.SetBGGUsername(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestSetBGGUsername_InvalidBody(t *testing.T) {
	h := NewHandler(NewService(&mockProfileStore{}))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("PUT", "/api/v1/profile/bgg-username", "bad json")
	h.SetBGGUsername(w, r)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestSetBGGUsername_Success(t *testing.T) {
	store := &mockProfileStore{
		upsertProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			return &Profile{ID: userID}, nil
		},
		setBGGUsernameFn: func(ctx context.Context, userID, bggUsername string) error {
			return nil
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("PUT", "/api/v1/profile/bgg-username", `{"bgg_username":"myhandle"}`)
	h.SetBGGUsername(w, r)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
}

func TestSetBGGUsername_NotFound(t *testing.T) {
	store := &mockProfileStore{
		upsertProfileFn: func(ctx context.Context, userID string) (*Profile, error) {
			return &Profile{ID: userID}, nil
		},
		setBGGUsernameFn: func(ctx context.Context, userID, bggUsername string) error {
			return apierr.ErrNotFound
		},
	}
	h := NewHandler(NewService(store))
	w := httptest.NewRecorder()
	r := newAuthenticatedRequest("PUT", "/api/v1/profile/bgg-username", `{"bgg_username":"myhandle"}`)
	h.SetBGGUsername(w, r)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func strPtr(s string) *string { return &s }

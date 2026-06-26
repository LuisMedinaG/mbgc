package profile

import "context"

// profileStore defines the store contract for handler testability.
type profileStore interface {
	GetProfile(ctx context.Context, userID string) (*Profile, error)
	UpsertProfile(ctx context.Context, userID string) (*Profile, error)
	SetBGGUsername(ctx context.Context, userID, bggUsername string) error
	GetBGGUsername(ctx context.Context, userID string) (string, error)
	GetTier(ctx context.Context, userID string) (string, error)
}

type Service struct {
	store profileStore
}

func NewService(st profileStore) *Service {
	return &Service{store: st}
}

// GetProfile returns the profile, creating it on first access (lazy upsert).
// ref: profile.VIEW.1 — GET /api/v1/profile with lazy upsert on first access
func (s *Service) GetProfile(ctx context.Context, userID string) (*Profile, error) {
	p, err := s.store.GetProfile(ctx, userID)
	if err == nil {
		return p, nil
	}
	return s.store.UpsertProfile(ctx, userID)
}

func (s *Service) SetBGGUsername(ctx context.Context, userID, bggUsername string) error {
	if _, err := s.store.UpsertProfile(ctx, userID); err != nil {
		return err
	}
	return s.store.SetBGGUsername(ctx, userID, bggUsername)
}

// GetBGGUsername returns the configured BGG handle, or "" if unset.
func (s *Service) GetBGGUsername(ctx context.Context, userID string) (string, error) {
	return s.store.GetBGGUsername(ctx, userID)
}

// GetTier returns the user's tier ("basic" or "pro").
func (s *Service) GetTier(ctx context.Context, userID string) (string, error) {
	return s.store.GetTier(ctx, userID)
}

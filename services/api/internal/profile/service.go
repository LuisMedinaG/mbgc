package profile

import "context"

type Service struct {
	store *Store
}

func NewService(st *Store) *Service {
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

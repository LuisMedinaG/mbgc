package service

import (
	"context"

	"github.com/LuisMedinaG/mbgc/services/auth/internal/model"
	"github.com/LuisMedinaG/mbgc/services/auth/internal/store"
)

type Service struct {
	store *store.Store
}

func New(st *store.Store) *Service {
	return &Service{store: st}
}

// GetProfile returns the profile, creating it on first access (lazy upsert).
func (s *Service) GetProfile(ctx context.Context, userID string) (*model.Profile, error) {
	p, err := s.store.GetProfile(ctx, userID)
	if err == nil {
		return p, nil
	}
	// First time this user hits the API — create their profile row
	return s.store.UpsertProfile(ctx, userID)
}

func (s *Service) SetBGGUsername(ctx context.Context, userID, bggUsername string) error {
	// Ensure profile row exists before updating
	if _, err := s.store.UpsertProfile(ctx, userID); err != nil {
		return err
	}
	return s.store.SetBGGUsername(ctx, userID, bggUsername)
}

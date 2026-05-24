package service

import (
	"context"

	"github.com/LuisMedinaG/mbgc/services/game/internal/model"
	"github.com/LuisMedinaG/mbgc/services/game/internal/store"
)

type Service struct {
	store *store.Store
}

func New(st *store.Store) *Service {
	return &Service{store: st}
}

func (s *Service) ListGames(ctx context.Context, userID string, f model.GameFilter) ([]model.Game, int, error) {
	return s.store.ListGames(ctx, userID, f)
}

func (s *Service) GetGame(ctx context.Context, id int64, userID string) (*model.Game, error) {
	return s.store.GetGame(ctx, id, userID)
}

func (s *Service) DeleteGame(ctx context.Context, id int64, userID string) error {
	return s.store.DeleteGame(ctx, id, userID)
}

func (s *Service) ListCollections(ctx context.Context, userID string) ([]model.Collection, error) {
	return s.store.ListCollections(ctx, userID)
}

func (s *Service) CreateCollection(ctx context.Context, userID, name, description string) (*model.Collection, error) {
	return s.store.CreateCollection(ctx, userID, name, description)
}

func (s *Service) UpdateCollection(ctx context.Context, id int64, userID, name, description string) error {
	return s.store.UpdateCollection(ctx, id, userID, name, description)
}

func (s *Service) DeleteCollection(ctx context.Context, id int64, userID string) error {
	return s.store.DeleteCollection(ctx, id, userID)
}

func (s *Service) SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error {
	return s.store.SetGameCollections(ctx, userID, gameID, collectionIDs)
}

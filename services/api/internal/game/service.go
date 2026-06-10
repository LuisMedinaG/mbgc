package game

import "context"

type gameStore interface {
	ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error)
	GetGame(ctx context.Context, id int64, userID string) (*Game, error)
	CreateGame(ctx context.Context, userID string, bggID int) (int64, error)
	GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error)
	UpsertBGGGame(ctx context.Context, userID string, g BGGGameData) (int64, bool, error)
	DeleteGame(ctx context.Context, id int64, userID string) error
	ListCollections(ctx context.Context, userID string) ([]Collection, error)
	CreateCollection(ctx context.Context, userID, name, description string) (*Collection, error)
	UpdateCollection(ctx context.Context, id int64, userID, name, description string) error
	DeleteCollection(ctx context.Context, id int64, userID string) error
	SetGameCollections(ctx context.Context, userID string, gameID int64, collectionIDs []int64) error
	UpdateRulesURL(ctx context.Context, gameID int64, userID, rulesURL string) error
	Discover(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error)
}

type Service struct {
	store gameStore
}

func NewService(st gameStore) *Service {
	return &Service{store: st}
}

func (s *Service) ListGames(ctx context.Context, userID string, f GameFilter) ([]Game, int, error) {
	return s.store.ListGames(ctx, userID, f)
}

func (s *Service) GetGame(ctx context.Context, id int64, userID string) (*Game, error) {
	return s.store.GetGame(ctx, id, userID)
}

func (s *Service) DeleteGame(ctx context.Context, id int64, userID string) error {
	return s.store.DeleteGame(ctx, id, userID)
}

func (s *Service) ListCollections(ctx context.Context, userID string) ([]Collection, error) {
	return s.store.ListCollections(ctx, userID)
}

func (s *Service) CreateCollection(ctx context.Context, userID, name, description string) (*Collection, error) {
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

// UpdateRulesURL sets the rules URL for a game after server-side validation.
func (s *Service) UpdateRulesURL(ctx context.Context, gameID int64, userID, rulesURL string) error {
	return s.store.UpdateRulesURL(ctx, gameID, userID, rulesURL)
}

// CreateGame creates a game by BGG ID — called by the importer.
func (s *Service) CreateGame(ctx context.Context, userID string, bggID int) (int64, error) {
	return s.store.CreateGame(ctx, userID, bggID)
}

// GameExistsByBGGID checks if a game already exists — called by the importer.
func (s *Service) GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error) {
	return s.store.GameExistsByBGGID(ctx, userID, bggID)
}

func (s *Service) Discover(ctx context.Context, userID string, f DiscoverFilter) ([]Game, int, *Collection, error) {
	return s.store.Discover(ctx, userID, f)
}

// UpsertBGGGame creates or updates a game from BGG data — called by the importer.
func (s *Service) UpsertBGGGame(ctx context.Context, userID string, g BGGGameData) (int64, bool, error) {
	return s.store.UpsertBGGGame(ctx, userID, g)
}

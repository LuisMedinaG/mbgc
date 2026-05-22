// Package model defines domain types for game-service.
package model

import "time"

// Game represents a board game in a user's collection.
type Game struct {
	ID                 int64        `json:"id"`
	UserID             string       `json:"-"`
	BGGID              int          `json:"bgg_id,omitempty"`
	Name               string       `json:"name"`
	Description        string       `json:"description,omitempty"`
	YearPublished      int          `json:"year_published,omitempty"`
	Image              string       `json:"image,omitempty"`
	Thumbnail          string       `json:"thumbnail,omitempty"`
	MinPlayers         int          `json:"min_players,omitempty"`
	MaxPlayers         int          `json:"max_players,omitempty"`
	Playtime           int          `json:"playtime,omitempty"`
	Categories         []string     `json:"categories,omitempty"`
	Mechanics          []string     `json:"mechanics,omitempty"`
	Types              []string     `json:"types,omitempty"`
	Weight             float64      `json:"weight,omitempty"`
	Rating             float64      `json:"rating,omitempty"`
	LanguageDependence int          `json:"language_dependence,omitempty"`
	RecommendedPlayers []int        `json:"recommended_players,omitempty"`
	RulesURL           string       `json:"rules_url,omitempty"`
	Collections        []Collection `json:"vibes,omitempty"` // "vibes" key for React app compatibility
	PlayerAids         []PlayerAid  `json:"player_aids,omitempty"`
	CreatedAt          time.Time    `json:"created_at"`
	UpdatedAt          time.Time    `json:"updated_at"`
}

// Collection is a user-defined group of games (internally called "vibes" in the old app).
type Collection struct {
	ID          int64     `json:"id"`
	UserID      string    `json:"-"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// PlayerAid is a file attachment (image) for a game.
type PlayerAid struct {
	ID       int64  `json:"id"`
	GameID   int64  `json:"game_id"`
	Filename string `json:"filename"`
	Label    string `json:"label,omitempty"`
}

// GameFilter holds query parameters for the list endpoint.
type GameFilter struct {
	Search     string
	Category   string
	Players    int
	Playtime   int
	Weight     float64
	Rating     float64
	Language   int
	RecPlayers int
	Page       int
	Limit      int
}

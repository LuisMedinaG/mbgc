package catalog

import "time"

type Game struct {
	ID                 int64     `json:"id"`
	UserID             string    `json:"user_id"`
	BGGID              *int      `json:"bgg_id,omitempty"`
	Name               string    `json:"name"`
	Description        *string   `json:"description,omitempty"`
	YearPublished      *int      `json:"year_published,omitempty"`
	Image              *string   `json:"image,omitempty"`
	Thumbnail          *string   `json:"thumbnail,omitempty"`
	MinPlayers         *int      `json:"min_players,omitempty"`
	MaxPlayers         *int      `json:"max_players,omitempty"`
	Playtime           *int      `json:"playtime,omitempty"`
	Categories         []string  `json:"categories"`
	Mechanics          []string  `json:"mechanics"`
	Types              []string  `json:"types"`
	Weight             *float64  `json:"weight,omitempty"`
	Rating             *float64  `json:"rating,omitempty"`
	LanguageDependence *int      `json:"language_dependence,omitempty"`
	RecommendedPlayers []int     `json:"recommended_players"`
	RulesURL           *string   `json:"rules_url,omitempty"`
	Vibes              []VibeRef `json:"vibes"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// VibeRef is the collection (id, name) pair attached to a game's "vibes" —
// the user-facing name for collection membership.
type VibeRef struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type GameFilter struct {
	Search   string
	Category string
	Players  string
	Playtime string
	Weight   string
	Page     int
	Limit    int
}

type Collection struct {
	ID          int64     `json:"id"`
	UserID      string    `json:"user_id"`
	Name        string    `json:"name"`
	Description *string   `json:"description,omitempty"`
	GameCount   int       `json:"game_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

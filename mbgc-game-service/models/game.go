package models

import "time"

type Game struct {
	ID            string    `json:"id"`
	BggID         *int      `json:"bgg_id,omitempty"`
	Title         string    `json:"title"`
	YearPublished *int      `json:"year_published,omitempty"`
	MinPlayers    *int      `json:"min_players,omitempty"`
	MaxPlayers    *int      `json:"max_players,omitempty"`
	Weight        *float64  `json:"weight,omitempty"`
	ImageURL      *string   `json:"image_url,omitempty"`
	Description   *string   `json:"description,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type CollectionEntry struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	GameID    string    `json:"game_id"`
	Status    string    `json:"status"`
	Rating    *int      `json:"rating,omitempty"`
	Notes     *string   `json:"notes,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type PlayerAid struct {
	ID              string    `json:"id"`
	GameID          string    `json:"game_id"`
	UploadedBy      string    `json:"uploaded_by"`
	Filename        string    `json:"filename"`
	ContentType     string    `json:"content_type"`
	SizeBytes       int64     `json:"size_bytes"`
	CreatedAt       time.Time `json:"created_at"`
	DataForDownload []byte    `json:"-"`
}

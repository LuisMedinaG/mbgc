package profile

import "time"

type Profile struct {
	ID          string    `json:"id"`
	Username    string    `json:"username"`
	BGGUsername *string   `json:"bgg_username"`
	IsAdmin     bool      `json:"is_admin"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

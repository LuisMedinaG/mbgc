package models

import "time"

type Profile struct {
	UserID      string    `json:"user_id"`
	Email       string    `json:"email"`
	BGGUsername *string   `json:"bgg_username"`
	Role        string    `json:"role"`
	ImportQuota int       `json:"import_quota"`
	ImportsUsed int       `json:"imports_used"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

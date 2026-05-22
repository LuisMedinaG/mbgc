// Package model defines domain types for auth-service.
// Authentication (login/signup/logout) is handled by Supabase Auth.
// This service manages application-level profile data stored in the profile schema.
package model

import "time"

// Profile is the application-level user profile.
// The id field is the Supabase Auth user UUID (auth.users.id).
type Profile struct {
	ID          string    `json:"id"`
	BGGUsername string    `json:"bgg_username,omitempty"`
	IsAdmin     bool      `json:"is_admin"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

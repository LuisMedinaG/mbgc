// Package model defines domain types for importer-service.
package model

import "time"

// SyncResult summarises the outcome of a BGG collection sync.
type SyncResult struct {
	Imported int      `json:"imported"`
	Skipped  int      `json:"skipped"`
	Failed   []string `json:"failed,omitempty"`
}

// CSVPreviewRow is a single row returned from the CSV preview endpoint.
type CSVPreviewRow struct {
	BGGID int    `json:"bgg_id"`
	Name  string `json:"name,omitempty"`
}

// RateLimit tracks daily sync usage for a user.
type RateLimit struct {
	UserID    string    `json:"user_id"`
	Count     int       `json:"count"`
	ResetDate time.Time `json:"reset_date"`
}

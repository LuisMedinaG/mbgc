package importer

import "time"

type SyncResult struct {
	Imported int      `json:"imported"`
	Skipped  int      `json:"skipped"`
	Failed   []string `json:"failed,omitempty"`
}

type CSVPreviewRow struct {
	BGGID int    `json:"bgg_id"`
	Name  string `json:"name,omitempty"`
}

type RateLimit struct {
	UserID    string    `json:"user_id"`
	Count     int       `json:"count"`
	ResetDate time.Time `json:"reset_date"`
}

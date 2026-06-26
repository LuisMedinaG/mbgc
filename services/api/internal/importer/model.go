package importer

type SyncResult struct {
	Imported    int      `json:"imported"`
	Skipped     int      `json:"skipped"`
	Failed      []string `json:"failed,omitempty"`
	ImportedIDs []int64  `json:"imported_ids,omitempty"` // local game IDs created this sync — lets the client add them to a list
}

// PreviewResult is the BGG collection pre-fetch: counts only, no metadata fetch (fast).
type PreviewResult struct {
	Total int `json:"total"`
	Owned int `json:"owned"`
	New   int `json:"new"`
}

type CSVPreviewRow struct {
	BGGID int    `json:"bgg_id"`
	Name  string `json:"name,omitempty"`
}

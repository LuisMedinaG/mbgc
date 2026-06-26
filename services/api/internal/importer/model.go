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

// SyncLimits bundles the per-tier BGG sync quotas passed through the handler → service → store.
type SyncLimits struct {
	Basic int // max syncs per week for basic users
	Pro   int // max syncs per day for pro users (≈hourly)
	Admin int // hard daily cap for admins (safety net, not a business limit)
}

type CSVPreviewRow struct {
	BGGID int    `json:"bgg_id"`
	Name  string `json:"name,omitempty"`
}

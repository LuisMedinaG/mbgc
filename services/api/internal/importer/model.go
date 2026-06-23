package importer

type SyncResult struct {
	Imported int      `json:"imported"`
	Skipped  int      `json:"skipped"`
	Failed   []string `json:"failed,omitempty"`
}

type CSVPreviewRow struct {
	BGGID int    `json:"bgg_id"`
	Name  string `json:"name,omitempty"`
}

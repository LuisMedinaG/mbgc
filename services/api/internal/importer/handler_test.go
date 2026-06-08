package importer

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
	"github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
	"github.com/LuisMedinaG/mbgc/services/api/internal/game"
)

type mockImporterStore struct {
	checkRateLimitFn func(ctx context.Context, userID string, isAdmin bool, limitUser, limitAdmin int) error
	recordSyncFn     func(ctx context.Context, userID string) error
	logSyncFn        func(ctx context.Context, userID string, imported int, fullRefresh bool) error
}

func (m *mockImporterStore) CheckRateLimit(ctx context.Context, userID string, isAdmin bool, lu, la int) error {
	return m.checkRateLimitFn(ctx, userID, isAdmin, lu, la)
}
func (m *mockImporterStore) RecordSync(ctx context.Context, userID string) error {
	return m.recordSyncFn(ctx, userID)
}
func (m *mockImporterStore) LogSync(ctx context.Context, userID string, imported int, fullRefresh bool) error {
	return m.logSyncFn(ctx, userID, imported, fullRefresh)
}

type mockBGGClient struct {
	available        bool
	fetchCollectionFn func(ctx context.Context, bggUsername string) ([]int, error)
	fetchGamesFn      func(ctx context.Context, bggIDs []int) ([]BGGGame, error)
}

func (m *mockBGGClient) Available() bool { return m.available }
func (m *mockBGGClient) FetchCollection(ctx context.Context, bggUsername string) ([]int, error) {
	if m.fetchCollectionFn != nil {
		return m.fetchCollectionFn(ctx, bggUsername)
	}
	return nil, nil
}
func (m *mockBGGClient) FetchGames(ctx context.Context, bggIDs []int) ([]BGGGame, error) {
	if m.fetchGamesFn != nil {
		return m.fetchGamesFn(ctx, bggIDs)
	}
	return nil, nil
}

type mockGameService struct {
	gameExistsFn   func(ctx context.Context, userID string, bggID int) (bool, error)
	upsertBGGGameFn func(ctx context.Context, userID string, g game.BGGGameData) (int64, bool, error)
}

func (m *mockGameService) GameExistsByBGGID(ctx context.Context, userID string, bggID int) (bool, error) {
	if m.gameExistsFn != nil {
		return m.gameExistsFn(ctx, userID, bggID)
	}
	return false, nil
}
func (m *mockGameService) UpsertBGGGame(ctx context.Context, userID string, g game.BGGGameData) (int64, bool, error) {
	if m.upsertBGGGameFn != nil {
		return m.upsertBGGGameFn(ctx, userID, g)
	}
	return 0, true, nil
}

type mockProfileService struct {
	getBGGUsernameFn func(ctx context.Context, userID string) (string, error)
}

func (m *mockProfileService) GetBGGUsername(ctx context.Context, userID string) (string, error) {
	if m.getBGGUsernameFn != nil {
		return m.getBGGUsernameFn(ctx, userID)
	}
	return "mytestuser", nil
}

func okStore() *mockImporterStore {
	return &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error { return nil },
		recordSyncFn:     func(ctx context.Context, userID string) error { return nil },
		logSyncFn:        func(ctx context.Context, userID string, imported int, fullRefresh bool) error { return nil },
	}
}

func authReq(method, path, body string, isAdmin bool) *http.Request {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "bgguser", isAdmin)
	return r.WithContext(ctx)
}

func mkHandler(store importerStore, bgg bggClient, gs gameService) *Handler {
	return NewHandler(NewService(store, bgg, gs, &mockProfileService{}), 3, 20)
}

func TestSync_Unauthenticated(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, httptest.NewRequest("POST", "/api/v1/import/sync", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestSync_BGGNotConfigured(t *testing.T) {
	h := mkHandler(okStore(), &mockBGGClient{available: false}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}
}

func TestSync_RateLimited(t *testing.T) {
	store := &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error {
			return apierr.ErrRateLimit
		},
		recordSyncFn: func(ctx context.Context, userID string) error { return nil },
		logSyncFn:    func(ctx context.Context, userID string, imported int, fullRefresh bool) error { return nil },
	}
	h := mkHandler(store, &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", w.Code)
	}
}

func TestSync_Success(t *testing.T) {
	h := mkHandler(okStore(), &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.Response[SyncResult]
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
}

func TestSync_FullRefreshNonAdmin(t *testing.T) {
	var got bool
	store := &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error { return nil },
		recordSyncFn:     func(ctx context.Context, userID string) error { return nil },
		logSyncFn: func(ctx context.Context, userID string, imported int, fr bool) error {
			got = fr
			return nil
		},
	}
	h := mkHandler(store, &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync?full_refresh=true", "", false))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if got {
		t.Fatal("non-admin must not trigger full_refresh")
	}
}

func TestSync_FullRefreshAdmin(t *testing.T) {
	var got bool
	store := &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error { return nil },
		recordSyncFn:     func(ctx context.Context, userID string) error { return nil },
		logSyncFn: func(ctx context.Context, userID string, imported int, fr bool) error {
			got = fr
			return nil
		},
	}
	h := mkHandler(store, &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync?full_refresh=true", "", true))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !got {
		t.Fatal("admin must trigger full_refresh")
	}
}

func multipartCSV(t *testing.T, content string) *http.Request {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	part, _ := w.CreateFormFile("csv_file", "test.csv")
	io.WriteString(part, content)
	w.Close()
	r := httptest.NewRequest("POST", "/api/v1/import/csv/preview", &buf)
	r.Header.Set("Content-Type", w.FormDataContentType())
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "bgguser", false)
	return r.WithContext(ctx)
}

func TestCSVPreview_NoFile(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/import/csv/preview", strings.NewReader("x"))
	r.Header.Set("Content-Type", "application/json")
	ctx := httpx.SetGatewayUser(r.Context(), "user-1", "bgguser", false)
	h.CSVPreview(w, r.WithContext(ctx))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestCSVPreview_ValidCSV(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVPreview(w, multipartCSV(t, "objectid,objectname\n174430,Gloomhaven\n167791,Terraforming Mars\n"))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.ListResponse[CSVPreviewRow]
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Data) != 2 || resp.Data[0].BGGID != 174430 || resp.Data[0].Name != "Gloomhaven" {
		t.Fatalf("unexpected: %+v", resp)
	}
}

func TestCSVPreview_MissingObjectIDColumn(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVPreview(w, multipartCSV(t, "name,year\nGloomhaven,2017\n"))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestCSVPreview_AltColumnNames(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVPreview(w, multipartCSV(t, "bgg_id,name\n12345,TestGame\n"))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.ListResponse[CSVPreviewRow]
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Data) != 1 || resp.Data[0].BGGID != 12345 {
		t.Fatalf("unexpected: %+v", resp)
	}
}

func TestCSVPreview_EmptyCSV(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVPreview(w, multipartCSV(t, ""))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestCSVPreview_SkipsInvalidRows(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVPreview(w, multipartCSV(t, "objectid,name\n174430,Gloomhaven\nnotanumber,Bad\n167791,TM\n"))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.ListResponse[CSVPreviewRow]
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Data) != 2 {
		t.Fatalf("expected 2 valid rows, got %d", len(resp.Data))
	}
}

func TestCSVImport_Unauthenticated(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "/api/v1/import/csv", strings.NewReader(`{"bgg_ids":[1]}`))
	r.Header.Set("Content-Type", "application/json")
	h.CSVImport(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestCSVImport_InvalidBody(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVImport(w, authReq("POST", "/api/v1/import/csv", "bad", false))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestCSVImport_EmptyIDs(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	h.CSVImport(w, authReq("POST", "/api/v1/import/csv", `{"bgg_ids":[]}`, false))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

// ref: importer.CSV_IMPORT.6 — reject batches > 100 to prevent amplification DoS.
func TestCSVImport_RejectsOversizedBatch(t *testing.T) {
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{}, &mockGameService{})
	w := httptest.NewRecorder()
	ids := make([]int, 0, 101)
	for i := 0; i < 101; i++ {
		ids = append(ids, i+1)
	}
	body, _ := json.Marshal(map[string]any{"bgg_ids": ids})
	h.CSVImport(w, authReq("POST", "/api/v1/import/csv", string(body), false))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 101 ids, got %d", w.Code)
	}
}

func TestCSVImport_DeduplicatesExisting(t *testing.T) {
	gs := &mockGameService{
		gameExistsFn: func(ctx context.Context, userID string, bggID int) (bool, error) {
			return bggID == 174430, nil
		},
		upsertBGGGameFn: func(ctx context.Context, userID string, g game.BGGGameData) (int64, bool, error) {
			return int64(g.BGGID), true, nil
		},
	}
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{available: true}, gs)
	w := httptest.NewRecorder()
	h.CSVImport(w, authReq("POST", "/api/v1/import/csv", `{"bgg_ids":[174430,167791]}`, false))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.Response[SyncResult]
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Data.Imported != 1 || resp.Data.Skipped != 1 {
		t.Fatalf("expected 1 imported + 1 skipped, got %+v", resp.Data)
	}
}

func TestCSVImport_AllNew(t *testing.T) {
	gs := &mockGameService{
		gameExistsFn: func(ctx context.Context, userID string, bggID int) (bool, error) { return false, nil },
		upsertBGGGameFn: func(ctx context.Context, userID string, g game.BGGGameData) (int64, bool, error) {
			return int64(g.BGGID), true, nil
		},
	}
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{available: true}, gs)
	w := httptest.NewRecorder()
	h.CSVImport(w, authReq("POST", "/api/v1/import/csv", `{"bgg_ids":[1,2,3]}`, false))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.Response[SyncResult]
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Data.Imported != 3 {
		t.Fatalf("expected 3 imported, got %d", resp.Data.Imported)
	}
}

func TestCSVImport_CreateFails(t *testing.T) {
	gs := &mockGameService{
		gameExistsFn: func(ctx context.Context, userID string, bggID int) (bool, error) { return false, nil },
		upsertBGGGameFn: func(ctx context.Context, userID string, g game.BGGGameData) (int64, bool, error) {
			return 0, false, apierr.ErrInternal
		},
	}
	h := mkHandler(&mockImporterStore{}, &mockBGGClient{available: true}, gs)
	w := httptest.NewRecorder()
	h.CSVImport(w, authReq("POST", "/api/v1/import/csv", `{"bgg_ids":[1,2]}`, false))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp envelope.Response[SyncResult]
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Data.Imported != 0 || len(resp.Data.Failed) != 2 {
		t.Fatalf("expected 0 imported + 2 failed, got %+v", resp.Data)
	}
}

func TestNewClient_NilWhenEmpty(t *testing.T) {
	if c := NewClient("", ""); c != nil {
		t.Fatal("expected nil")
	}
}

func TestNewClient_AvailableWithToken(t *testing.T) {
	c := NewClient("tok", "")
	if c == nil || !c.Available() {
		t.Fatal("expected available")
	}
}

func TestNewClient_AvailableWithCookie(t *testing.T) {
	c := NewClient("", "cookie")
	if c == nil || !c.Available() {
		t.Fatal("expected available")
	}
}

func TestTruncateToDay(t *testing.T) {
	in := time.Date(2025, 6, 4, 15, 30, 45, 123, time.UTC)
	out := truncateToDay(in)
	if out.Hour() != 0 || out.Minute() != 0 || out.Second() != 0 || out.Nanosecond() != 0 {
		t.Fatalf("expected zeroed time parts, got %v", out)
	}
	if out.Year() != 2025 || out.Month() != 6 || out.Day() != 4 {
		t.Fatalf("expected same date, got %v", out)
	}
}

// ref: monitoring.SINK.5 — capture slog JSON output for sink assertions
// captureSlog swaps slog.Default to a JSON handler writing to a buffer for
// the duration of the test, then restores the previous default.
func captureSlog(t *testing.T) *bytes.Buffer {
	t.Helper()
	buf := &bytes.Buffer{}
	prev := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(buf, &slog.HandlerOptions{Level: slog.LevelInfo})))
	t.Cleanup(func() { slog.SetDefault(prev) })
	return buf
}

// ref: monitoring.SINK.6 — decode newline-delimited JSON log records
// decodeLines parses every JSON line in buf.
func decodeLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimRight(buf.String(), "\n"), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("failed to parse log line %q: %v", line, err)
		}
		out = append(out, m)
	}
	return out
}

// ref: monitoring.SINK.7 — find first log record for a given event
func findEvent(records []map[string]any, event string) map[string]any {
	for _, r := range records {
		if r["event"] == event {
			return r
		}
	}
	return nil
}

// ref: monitoring.SINK.5 — successful sync emits sync_start and sync_ok with sync_kind
func TestSync_EmitsSyncStartAndSyncOk(t *testing.T) {
	buf := captureSlog(t)
	h := mkHandler(okStore(), &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	recs := decodeLines(t, buf)
	start := findEvent(recs, "sync_start")
	if start == nil {
		t.Fatalf("expected sync_start event, got %d records: %s", len(recs), buf.String())
	}
	if start["level"] != "INFO" {
		t.Errorf("expected sync_start level=INFO, got %v", start["level"])
	}
	if start["sync_kind"] != "incremental" {
		t.Errorf("expected sync_kind=incremental, got %v", start["sync_kind"])
	}

	ok := findEvent(recs, "sync_ok")
	if ok == nil {
		t.Fatalf("expected sync_ok event, got: %s", buf.String())
	}
	if ok["level"] != "INFO" {
		t.Errorf("expected sync_ok level=INFO, got %v", ok["level"])
	}
	if ok["sync_kind"] != "incremental" {
		t.Errorf("expected sync_kind=incremental, got %v", ok["sync_kind"])
	}
	if ok["game_count"] != float64(0) {
		t.Errorf("expected game_count=0, got %v", ok["game_count"])
	}

	if findEvent(recs, "sync_error") != nil {
		t.Errorf("did not expect sync_error on success, got: %s", buf.String())
	}
}

// ref: monitoring.SINK.5 — full_refresh sync_kind flows through to the event
func TestSync_FullRefreshEmitsFullRefreshKind(t *testing.T) {
	buf := captureSlog(t)
	h := mkHandler(okStore(), &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync?full_refresh=true", "", true))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	recs := decodeLines(t, buf)
	start := findEvent(recs, "sync_start")
	if start == nil || start["sync_kind"] != "full_refresh" {
		t.Errorf("expected sync_start sync_kind=full_refresh, got %v", start)
	}
	ok := findEvent(recs, "sync_ok")
	if ok == nil || ok["sync_kind"] != "full_refresh" {
		t.Errorf("expected sync_ok sync_kind=full_refresh, got %v", ok)
	}
}

// ref: monitoring.SINK.5 — BGG unconfigured emits sync_error at error level,
// no sync_start fires (the rejection happens before sync begins).
func TestSync_EmitsSyncErrorOnBGGUnconfigured(t *testing.T) {
	buf := captureSlog(t)
	h := mkHandler(okStore(), &mockBGGClient{available: false}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}

	recs := decodeLines(t, buf)
	errEv := findEvent(recs, "sync_error")
	if errEv == nil {
		t.Fatalf("expected sync_error event, got: %s", buf.String())
	}
	if errEv["level"] != "ERROR" {
		t.Errorf("expected sync_error level=ERROR for config failure, got %v", errEv["level"])
	}
	if errEv["sync_kind"] != "incremental" {
		t.Errorf("expected sync_kind=incremental, got %v", errEv["sync_kind"])
	}
	if findEvent(recs, "sync_start") != nil {
		t.Errorf("did not expect sync_start before rejection, got: %s", buf.String())
	}
	if findEvent(recs, "sync_ok") != nil {
		t.Errorf("did not expect sync_ok on error path, got: %s", buf.String())
	}
}

// ref: monitoring.SINK.5 — rate-limit emits sync_error at warn level
// (per-handoff: rate-limit is abuse signal, not a server fault).
func TestSync_EmitsSyncErrorOnRateLimited(t *testing.T) {
	buf := captureSlog(t)
	store := &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error {
			return apierr.ErrRateLimit
		},
		recordSyncFn: func(ctx context.Context, userID string) error { return nil },
		logSyncFn:    func(ctx context.Context, userID string, imported int, fr bool) error { return nil },
	}
	h := mkHandler(store, &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", w.Code)
	}

	recs := decodeLines(t, buf)
	errEv := findEvent(recs, "sync_error")
	if errEv == nil {
		t.Fatalf("expected sync_error event, got: %s", buf.String())
	}
	if errEv["level"] != "WARN" {
		t.Errorf("expected sync_error level=WARN for rate-limit, got %v", errEv["level"])
	}
	if findEvent(recs, "sync_start") != nil {
		t.Errorf("did not expect sync_start before rejection, got: %s", buf.String())
	}
}

// ref: monitoring.SINK.5 — non-rate-limit store failure during CheckRateLimit
// emits sync_error at error level (real server fault, not abuse).
func TestSync_EmitsSyncErrorOnCheckRateLimitServerFailure(t *testing.T) {
	buf := captureSlog(t)
	store := &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error {
			return apierr.ErrInternal
		},
		recordSyncFn: func(ctx context.Context, userID string) error { return nil },
		logSyncFn:    func(ctx context.Context, userID string, imported int, fr bool) error { return nil },
	}
	h := mkHandler(store, &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}

	recs := decodeLines(t, buf)
	errEv := findEvent(recs, "sync_error")
	if errEv == nil {
		t.Fatalf("expected sync_error event, got: %s", buf.String())
	}
	if errEv["level"] != "ERROR" {
		t.Errorf("expected sync_error level=ERROR for server fault, got %v", errEv["level"])
	}
}

// ref: monitoring.SINK.5 — store-layer failure after sync_start fires
// sync_error at error level and suppresses sync_ok.
func TestSync_EmitsSyncErrorOnStoreFailure(t *testing.T) {
	buf := captureSlog(t)
	store := &mockImporterStore{
		checkRateLimitFn: func(ctx context.Context, userID string, isAdmin bool, lu, la int) error { return nil },
		recordSyncFn:     func(ctx context.Context, userID string) error { return apierr.ErrInternal },
		logSyncFn:        func(ctx context.Context, userID string, imported int, fr bool) error { return nil },
	}
	h := mkHandler(store, &mockBGGClient{available: true}, &mockGameService{})
	w := httptest.NewRecorder()
	h.Sync(w, authReq("POST", "/api/v1/import/sync", "", false))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", w.Code)
	}

	recs := decodeLines(t, buf)
	if findEvent(recs, "sync_start") == nil {
		t.Errorf("expected sync_start before store failure, got: %s", buf.String())
	}
	errEv := findEvent(recs, "sync_error")
	if errEv == nil {
		t.Fatalf("expected sync_error event, got: %s", buf.String())
	}
	if errEv["level"] != "ERROR" {
		t.Errorf("expected sync_error level=ERROR for store failure, got %v", errEv["level"])
	}
	if findEvent(recs, "sync_ok") != nil {
		t.Errorf("did not expect sync_ok on store failure, got: %s", buf.String())
	}
}

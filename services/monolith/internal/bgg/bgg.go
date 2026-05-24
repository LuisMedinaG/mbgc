package bgg

import (
	"context"
	"encoding/xml"
	"fmt"
	"html"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/model"

	"github.com/fzerorubigd/gobgg"
)

// GameStore is the subset of the game data layer that the BGG client needs.
// services/games.Store satisfies this interface.
type GameStore interface {
	OwnedBGGIDs(userID int64) (map[int64]bool, error)
	CreateGame(g model.Game, userID int64) (int64, error)
	UpdateGame(g model.Game, userID int64) error
}

// Client wraps the BoardGameGeek API client.
type Client struct {
	bgg        *gobgg.BGG
	httpClient *http.Client // used for our own /xmlapi2/thing calls
}

// bggRPS is the maximum requests-per-second this process will send to BGG. BGG
// aggressively rate-limits the /xmlapi2 and /api endpoints and returns HTTP 429
// once you exceed roughly a few requests per second. 2/s is well under that
// and still syncs a ~120-game collection in about a minute.
const bggRPS = 2

// New creates a new BGG client with the given auth token.
func New(token string) *Client {
	token = strings.TrimSpace(token)
	hc := newHTTPClient(&authTransport{base: http.DefaultTransport, token: token})
	return &Client{
		bgg:        gobgg.NewBGGClient(gobgg.SetAuthToken(token), gobgg.SetClient(hc)),
		httpClient: hc,
	}
}

// NewWithCookies creates a new BGG client using a raw cookie string
// (e.g. "bggusername=foo; bggpassword=bar; SessionID=xyz").
func NewWithCookies(raw string) *Client {
	raw = strings.TrimSpace(raw)
	if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
		raw = raw[1 : len(raw)-1]
	}
	cookies := parseCookieString(raw)
	hc := newHTTPClient(&authTransport{base: http.DefaultTransport, cookies: cookies})
	return &Client{
		bgg:        gobgg.NewBGGClient(gobgg.SetCookies("", cookies), gobgg.SetClient(hc)),
		httpClient: hc,
	}
}

// newHTTPClient wraps an authTransport in a throttling/429-aware transport and
// returns an http.Client configured for BGG.
func newHTTPClient(auth *authTransport) *http.Client {
	return &http.Client{Transport: &throttledTransport{
		base:     auth,
		tick:     time.NewTicker(time.Second / bggRPS),
		maxRetry: 3,
	}}
}

// authTransport attaches auth cookies, a bearer token, and a User-Agent to every
// outgoing request. gobgg only wires cookies into a handful of endpoints
// (notably not /xmlapi2/thing), and BGG now returns HTTP 401 for unauthenticated
// /thing requests, which gobgg surfaces as "XML decoding failed: EOF". Doing it
// at the transport layer guarantees every call is authenticated.
type authTransport struct {
	base    http.RoundTripper
	cookies []*http.Cookie
	token   string
}

func (t *authTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req = req.Clone(req.Context())
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "github.com/LuisMedinaG/mbgc/services/monolith/1.0 (+https://github.com/LuisMedinaG/myboardgamecollection)")
	}
	// Token is the primary auth strategy; cookies are a workaround for local
	// dev when no token is available. Only fall back to cookies if no token.
	if t.token != "" {
		if req.Header.Get("Authorization") == "" {
			req.Header.Set("Authorization", "Bearer "+t.token)
		}
	} else {
		for _, c := range t.cookies {
			req.AddCookie(c)
		}
	}
	return t.base.RoundTrip(req)
}

// throttledTransport paces outgoing requests to BGG and transparently retries
// HTTP 429 responses, honoring the Retry-After header when present. This keeps
// rate-limit handling out of every individual endpoint caller (and gobgg never
// needs to know about it).
type throttledTransport struct {
	base     http.RoundTripper
	tick     *time.Ticker
	maxRetry int
}

func (t *throttledTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	for attempt := 0; ; attempt++ {
		// Pace outgoing requests.
		select {
		case <-t.tick.C:
		case <-req.Context().Done():
			return nil, req.Context().Err()
		}

		resp, err := t.base.RoundTrip(req)
		if err != nil {
			return nil, err
		}
		if resp.StatusCode != http.StatusTooManyRequests || attempt >= t.maxRetry {
			return resp, nil
		}

		// Got 429 — drain & close body, sleep, retry.
		wait := parseRetryAfter(resp.Header.Get("Retry-After"))
		if wait <= 0 {
			wait = time.Duration(1<<attempt) * time.Second // 1s, 2s, 4s
		}
		resp.Body.Close()
		slog.Warn("bgg rate limited; backing off", "attempt", attempt+1, "wait", wait, "url", req.URL.Path)
		select {
		case <-time.After(wait):
		case <-req.Context().Done():
			return nil, req.Context().Err()
		}
	}
}

// parseRetryAfter parses an HTTP Retry-After header (seconds or HTTP date).
// Returns 0 if unparseable.
func parseRetryAfter(v string) time.Duration {
	v = strings.TrimSpace(v)
	if v == "" {
		return 0
	}
	if secs, err := strconv.Atoi(v); err == nil && secs >= 0 {
		return time.Duration(secs) * time.Second
	}
	if t, err := http.ParseTime(v); err == nil {
		if d := time.Until(t); d > 0 {
			return d
		}
	}
	return 0
}

// parseCookieString parses a raw Cookie header value into []*http.Cookie.
func parseCookieString(raw string) []*http.Cookie {
	header := http.Header{"Cookie": {raw}}
	req := http.Request{Header: header}
	return req.Cookies()
}

// ---------------------------------------------------------------------------
// BGG /xmlapi2/thing — custom XML parsing
//
// gobgg's ThingResult does not expose raw poll data (language_dependence,
// suggested_numplayers), so we fetch /thing ourselves using our own XML
// structs. This lets us extract all fields — including polls — in a single
// request without doubling API calls.
// ---------------------------------------------------------------------------

const bggThingURL = "https://boardgamegeek.com/xmlapi2/thing"

// bggThingXMLItems is the top-level envelope of /xmlapi2/thing responses.
type bggThingXMLItems struct {
	XMLName xml.Name         `xml:"items"`
	Items   []bggThingXMLItem `xml:"item"`
}

type bggThingXMLItem struct {
	ID            int64            `xml:"id,attr"`
	Thumbnail     string           `xml:"thumbnail"`
	Image         string           `xml:"image"`
	Name          []bggNameXML     `xml:"name"`
	Description   string           `xml:"description"`
	YearPublished bggSimpleAttr    `xml:"yearpublished"`
	MinPlayers    bggSimpleAttr    `xml:"minplayers"`
	MaxPlayers    bggSimpleAttr    `xml:"maxplayers"`
	PlayingTime   bggSimpleAttr    `xml:"playingtime"`
	Link          []bggLinkXML     `xml:"link"`
	Poll          []bggPollXML     `xml:"poll"`
	Statistics    bggStatisticsXML `xml:"statistics"`
}

type bggNameXML struct {
	Type  string `xml:"type,attr"`
	Value string `xml:"value,attr"`
}

type bggSimpleAttr struct {
	Value string `xml:"value,attr"`
}

type bggLinkXML struct {
	Type  string `xml:"type,attr"`
	Value string `xml:"value,attr"`
}

type bggPollXML struct {
	Name    string           `xml:"name,attr"`
	Results []bggPollResults `xml:"results"`
}

type bggPollResults struct {
	NumPlayers string          `xml:"numplayers,attr"`
	Result     []bggPollResult `xml:"result"`
}

type bggPollResult struct {
	Value    string `xml:"value,attr"`
	NumVotes int    `xml:"numvotes,attr"`
	Level    string `xml:"level,attr"`
}

type bggStatisticsXML struct {
	Ratings bggRatingsXML `xml:"ratings"`
}

type bggRatingsXML struct {
	Average       bggSimpleAttr `xml:"average"`
	AverageWeight bggSimpleAttr `xml:"averageweight"`
}

// fetchThingsParsed fetches /xmlapi2/thing for the given IDs using our own
// authenticated, throttled httpClient and parses all fields we need —
// including polls that gobgg's ThingResult does not expose. Retries up to
// maxAttempts times on empty (queued) BGG responses.
func (c *Client) fetchThingsParsed(ctx context.Context, ids ...int64) ([]model.Game, error) {
	const maxAttempts = 4
	delay := 500 * time.Millisecond

	idStrs := make([]string, len(ids))
	for i, id := range ids {
		idStrs[i] = strconv.FormatInt(id, 10)
	}
	u := bggThingURL + "?id=" + strings.Join(idStrs, ",") + "&stats=1"

	for attempt := 1; ; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return nil, fmt.Errorf("build /thing request: %w", err)
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return nil, fmt.Errorf("fetching /thing bgg_ids=%v: %w", ids, err)
		}

		body, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			return nil, fmt.Errorf("reading /thing body: %w", readErr)
		}

		var result bggThingXMLItems
		if xmlErr := xml.Unmarshal(body, &result); xmlErr != nil || len(result.Items) == 0 {
			if attempt >= maxAttempts {
				if xmlErr != nil {
					return nil, fmt.Errorf("XML decode /thing bgg_ids=%v after %d attempts: %w", ids, attempt, xmlErr)
				}
				return nil, fmt.Errorf("empty /thing response for bgg_ids=%v after %d attempts", ids, attempt)
			}
			select {
			case <-time.After(delay):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
			delay *= 2
			continue
		}

		games := make([]model.Game, len(result.Items))
		for i, item := range result.Items {
			games[i] = bggItemToGame(item)
		}
		return games, nil
	}
}

// bggItemToGame converts a parsed BGG XML item into our Game model.
func bggItemToGame(item bggThingXMLItem) model.Game {
	var name string
	for _, n := range item.Name {
		if n.Type == "primary" {
			name = n.Value
			break
		}
	}

	var cats, mechs, types []string
	for _, l := range item.Link {
		switch l.Type {
		case "boardgamecategory":
			cats = append(cats, l.Value)
		case "boardgamemechanic":
			mechs = append(mechs, l.Value)
		case "boardgamesubdomain":
			types = append(types, l.Value)
		}
	}

	rating, _ := strconv.ParseFloat(item.Statistics.Ratings.Average.Value, 64)
	weight, _ := strconv.ParseFloat(item.Statistics.Ratings.AverageWeight.Value, 64)
	yearPublished, _ := strconv.Atoi(item.YearPublished.Value)
	minPlayers, _ := strconv.Atoi(item.MinPlayers.Value)
	maxPlayers, _ := strconv.Atoi(item.MaxPlayers.Value)
	playTime, _ := strconv.Atoi(item.PlayingTime.Value)

	return model.Game{
		BGGID:              item.ID,
		Name:               html.UnescapeString(name),
		Description:        html.UnescapeString(item.Description),
		YearPublished:      yearPublished,
		Image:              item.Image,
		Thumbnail:          item.Thumbnail,
		MinPlayers:         minPlayers,
		MaxPlayers:         maxPlayers,
		PlayTime:           playTime,
		Categories:         strings.Join(cats, ", "),
		Mechanics:          strings.Join(mechs, ", "),
		Types:              strings.Join(types, ", "),
		Weight:             weight,
		Rating:             rating,
		LanguageDependence: parseLanguageDependence(item.Poll),
		RecommendedPlayers: parseRecommendedPlayers(item.Poll),
	}
}

// parseLanguageDependence reads the "language_dependence" poll and returns the
// winning level (1–5), or 0 when the poll is absent or has no votes.
// BGG levels: 1=No necessary in-game text, 2=Some text, 3=Moderate,
// 4=Extensive, 5=Unplayable in another language.
func parseLanguageDependence(polls []bggPollXML) int {
	for _, p := range polls {
		if p.Name != "language_dependence" || len(p.Results) == 0 {
			continue
		}
		bestLevel, bestVotes := 0, -1
		for _, r := range p.Results[0].Result {
			level, err := strconv.Atoi(r.Level)
			if err != nil {
				continue
			}
			if r.NumVotes > bestVotes {
				bestVotes = r.NumVotes
				bestLevel = level
			}
		}
		if bestVotes <= 0 {
			return 0
		}
		return bestLevel
	}
	return 0
}

// parseRecommendedPlayers reads the "suggested_numplayers" poll and returns a
// comma-separated string (no spaces) of player counts where the community
// recommends playing (Best + Recommended votes > Not Recommended votes).
// Trailing "+" suffixes (e.g. "5+") are stripped so counts are plain numbers.
// Returns "" when the poll is absent or no count qualifies.
func parseRecommendedPlayers(polls []bggPollXML) string {
	for _, p := range polls {
		if p.Name != "suggested_numplayers" {
			continue
		}
		var rec []string
		for _, results := range p.Results {
			var best, recommended, notRec int
			for _, r := range results.Result {
				switch r.Value {
				case "Best":
					best = r.NumVotes
				case "Recommended":
					recommended = r.NumVotes
				case "Not Recommended":
					notRec = r.NumVotes
				}
			}
			if best+recommended > notRec {
				// Normalize "5+" → "5" so numeric filters work cleanly.
				count := strings.TrimRight(results.NumPlayers, "+")
				rec = append(rec, count)
			}
		}
		return strings.Join(rec, ",")
	}
	return ""
}

// ImportCollection syncs a user's BGG collection. When fullRefresh is false
// (the normal sync path) only games not already in the user's collection are
// fetched from BGG. When fullRefresh is true every owned item is re-fetched
// and its metadata updated — intended for admins and future paid tiers.
func (c *Client) ImportCollection(ctx context.Context, s GameStore, username string, userID int64, fullRefresh bool) (added, updated, collectionCount int, err error) {
	items, err := c.bgg.GetCollection(ctx, username, gobgg.SetCollectionTypes(gobgg.CollectionTypeOwn))
	if err != nil {
		return 0, 0, 0, fmt.Errorf("fetching collection for %q: %w", username, err)
	}
	collectionCount = len(items)

	owned, err := s.OwnedBGGIDs(userID)
	if err != nil {
		return 0, 0, collectionCount, fmt.Errorf("loading owned IDs: %w", err)
	}

	// Normal sync: only fetch games we don't already own (0 /thing calls when
	// nothing changed). Full refresh: fetch every item to update metadata.
	var idsToFetch []int64
	for _, item := range items {
		if fullRefresh || !owned[item.ID] {
			idsToFetch = append(idsToFetch, item.ID)
		}
	}

	if len(idsToFetch) == 0 {
		return 0, 0, collectionCount, nil
	}

	// Batch requests in groups of bggThingBatchSize to keep URL length
	// reasonable and match BGG's documented limit.
	var firstThingErr error
	thingFailures := 0
	for _, batch := range chunkIDs(idsToFetch, bggThingBatchSize) {
		games, fetchErr := c.fetchThingsParsed(ctx, batch...)
		if fetchErr != nil {
			if firstThingErr == nil {
				firstThingErr = fetchErr
			}
			thingFailures += len(batch)
			slog.Warn("bgg thing fetch failed", "batch_size", len(batch), "error", fetchErr)
			continue
		}
		for _, game := range games {
			if owned[game.BGGID] {
				if updateErr := s.UpdateGame(game, userID); updateErr == nil {
					updated++
				}
			} else {
				if _, createErr := s.CreateGame(game, userID); createErr == nil {
					added++
				}
			}
		}
	}

	if thingFailures == len(idsToFetch) {
		return added, updated, collectionCount, fmt.Errorf("could not load game details from BGG for any of %d collection item(s); last error: %w", len(idsToFetch), firstThingErr)
	}

	return added, updated, collectionCount, nil
}

// bggThingBatchSize is the max number of IDs per /thing request.
const bggThingBatchSize = 20

// chunkIDs splits ids into contiguous chunks of at most size.
func chunkIDs(ids []int64, size int) [][]int64 {
	if size <= 0 {
		return [][]int64{ids}
	}
	var out [][]int64
	for i := 0; i < len(ids); i += size {
		end := i + size
		if end > len(ids) {
			end = len(ids)
		}
		out = append(out, ids[i:end])
	}
	return out
}

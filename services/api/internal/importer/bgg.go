package importer

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

	"github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
	"github.com/fzerorubigd/gobgg"
)

// BGGGame is the subset of game data we fetch from BGG and persist via the
// game service. Mirrors fields in games.games table.
type BGGGame struct {
	BGGID              int
	Name               string
	Description        string
	YearPublished      int
	Image              string
	Thumbnail          string
	MinPlayers         int
	MaxPlayers         int
	PlayTime           int
	Categories         []string
	Mechanics          []string
	Types              []string
	Weight             float64
	Rating             float64
	LanguageDependence int
	RecommendedPlayers []int
}

// Client wraps the BGG API. Nil is valid — callers must check Available().
type Client struct {
	httpClient *http.Client
	token      string
	cookie     string
	bgg        *gobgg.BGG
}

const bggRPS = 2

// NewClient returns nil if neither token nor cookie is set.
func NewClient(token, cookie string) *Client {
	token = strings.TrimSpace(token)
	cookie = strings.TrimSpace(cookie)
	if len(cookie) >= 2 && cookie[0] == '"' && cookie[len(cookie)-1] == '"' {
		cookie = cookie[1 : len(cookie)-1]
	}
	if token == "" && cookie == "" {
		return nil
	}
	hc := newBGGHTTPClient(&bggAuthTransport{base: http.DefaultTransport, token: token, cookies: parseBGGCookieString(cookie)})
	return &Client{
		httpClient: hc,
		token:      token,
		cookie:     cookie,
		bgg:        gobgg.NewBGGClient(gobgg.SetAuthToken(token), gobgg.SetClient(hc)),
	}
}

// Available reports whether BGG credentials are configured.
func (c *Client) Available() bool {
	return c != nil
}

// newBGGHTTPClient wraps an authTransport in a throttling/429-aware transport.
func newBGGHTTPClient(auth *bggAuthTransport) *http.Client {
	return &http.Client{Transport: &throttledTransport{
		base:     auth,
		tick:     time.NewTicker(time.Second / bggRPS),
		maxRetry: 3,
	}}
}

type bggAuthTransport struct {
	base    http.RoundTripper
	cookies []*http.Cookie
	token   string
}

func (t *bggAuthTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req = req.Clone(req.Context())
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "github.com/LuisMedinaG/mbgc/services/api/1.0 (+https://github.com/LuisMedinaG/myboardgamecollection)")
	}
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

type throttledTransport struct {
	base     http.RoundTripper
	tick     *time.Ticker
	maxRetry int
}

func (t *throttledTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	for attempt := 0; ; attempt++ {
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
		wait := parseBGGRetryAfter(resp.Header.Get("Retry-After"))
		if wait <= 0 {
			wait = time.Duration(1<<attempt) * time.Second
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

func parseBGGRetryAfter(v string) time.Duration {
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

func parseBGGCookieString(raw string) []*http.Cookie {
	if raw == "" {
		return nil
	}
	header := http.Header{"Cookie": {raw}}
	req := http.Request{Header: header}
	return req.Cookies()
}

// FetchCollection fetches the owned games for a BGG username.
func (c *Client) FetchCollection(ctx context.Context, bggUsername string) ([]int, error) {
	items, err := c.bgg.GetCollection(ctx, bggUsername, gobgg.SetCollectionTypes(gobgg.CollectionTypeOwn))
	if err != nil {
		return nil, fmt.Errorf("fetching BGG collection for %q: %w", bggUsername, err)
	}
	ids := make([]int, 0, len(items))
	for _, it := range items {
		ids = append(ids, int(it.ID))
	}
	return ids, nil
}

// FetchGames fetches metadata for the given BGG IDs in batches.
func (c *Client) FetchGames(ctx context.Context, bggIDs []int) ([]BGGGame, error) {
	const batchSize = 20
	var allGames []BGGGame
	for i := 0; i < len(bggIDs); i += batchSize {
		end := i + batchSize
		if end > len(bggIDs) {
			end = len(bggIDs)
		}
		batch := bggIDs[i:end]
		games, err := c.fetchThingsParsed(ctx, batch)
		if err != nil {
			return nil, err
		}
		allGames = append(allGames, games...)
	}
	return allGames, nil
}

const bggThingURL = "https://boardgamegeek.com/xmlapi2/thing"

type bggThingXMLItems struct {
	XMLName xml.Name          `xml:"items"`
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

func (c *Client) fetchThingsParsed(ctx context.Context, ids []int) ([]BGGGame, error) {
	const maxAttempts = 4
	delay := 500 * time.Millisecond

	idStrs := make([]string, len(ids))
	for i, id := range ids {
		idStrs[i] = strconv.Itoa(id)
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
		games := make([]BGGGame, len(result.Items))
		for i, item := range result.Items {
			games[i] = bggItemToBGGGame(item)
		}
		return games, nil
	}
}

func bggItemToBGGGame(item bggThingXMLItem) BGGGame {
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

	return BGGGame{
		BGGID:              int(item.ID),
		Name:               html.UnescapeString(name),
		Description:        html.UnescapeString(item.Description),
		YearPublished:      yearPublished,
		Image:              item.Image,
		Thumbnail:          item.Thumbnail,
		MinPlayers:         minPlayers,
		MaxPlayers:         maxPlayers,
		PlayTime:           playTime,
		Categories:         cats,
		Mechanics:          mechs,
		Types:              types,
		Weight:             weight,
		Rating:             rating,
		LanguageDependence: parseLanguageDependence(item.Poll),
		RecommendedPlayers: parseRecommendedPlayers(item.Poll),
	}
}

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

func parseRecommendedPlayers(polls []bggPollXML) []int {
	for _, p := range polls {
		if p.Name != "suggested_numplayers" {
			continue
		}
		var rec []int
		seen := make(map[int]bool)
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
				countStr := strings.TrimRight(results.NumPlayers, "+")
				count, err := strconv.Atoi(countStr)
				if err == nil && !seen[count] {
					rec = append(rec, count)
					seen[count] = true
				}
			}
		}
		return rec
	}
	return nil
}

// silence unused import warning for httpx
var _ = httpx.DefaultClient

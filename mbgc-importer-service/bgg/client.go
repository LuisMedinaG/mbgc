package bgg

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

const bggCollectionURL = "https://boardgamegeek.com/xmlapi2/collection?username=%s&own=1&stats=1"

// BGGGame holds the parsed fields for a single board game from BGG.
type BGGGame struct {
	BGGID         int
	Title         string
	YearPublished int
	MinPlayers    int
	MaxPlayers    int
	Weight        float64
	ImageURL      string
}

// xmlCollection is the top-level BGG XML response.
type xmlCollection struct {
	Items []xmlItem `xml:"item"`
}

type xmlItem struct {
	ObjectID string  `xml:"objectid,attr"`
	Name     xmlName `xml:"name"`
	YearPub  xmlYear `xml:"yearpublished"`
	Stats    xmlStats `xml:"stats"`
	Image    string  `xml:"image"`
}

type xmlName struct {
	Value string `xml:",chardata"`
}

type xmlYear struct {
	Value string `xml:",chardata"`
}

type xmlStats struct {
	MinPlayers string      `xml:"minplayers,attr"`
	MaxPlayers string      `xml:"maxplayers,attr"`
	Rating     xmlRating   `xml:"rating"`
}

type xmlRating struct {
	Averages xmlAverages `xml:"averageweight"`
}

type xmlAverages struct {
	Value string `xml:"value,attr"`
}

// SearchGames fetches a user's owned BGG collection, retrying on 202 responses.
func SearchGames(ctx context.Context, username string) ([]BGGGame, error) {
	url := fmt.Sprintf(bggCollectionURL, username)

	const maxRetries = 5
	const retryDelay = 2 * time.Second

	var body []byte
	for attempt := 1; attempt <= maxRetries; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, fmt.Errorf("build request: %w", err)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return nil, fmt.Errorf("http get: %w", err)
		}

		if resp.StatusCode == http.StatusAccepted {
			resp.Body.Close()
			if attempt == maxRetries {
				return nil, fmt.Errorf("BGG returned 202 after %d retries", maxRetries)
			}
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(retryDelay):
			}
			continue
		}

		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			return nil, fmt.Errorf("BGG returned status %d", resp.StatusCode)
		}

		body, err = io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("read body: %w", err)
		}
		break
	}

	var col xmlCollection
	if err := xml.Unmarshal(body, &col); err != nil {
		return nil, fmt.Errorf("parse xml: %w", err)
	}

	games := make([]BGGGame, 0, len(col.Items))
	for _, item := range col.Items {
		g := BGGGame{
			Title:    item.Name.Value,
			ImageURL: item.Image,
		}
		if id, err := strconv.Atoi(item.ObjectID); err == nil {
			g.BGGID = id
		}
		if y, err := strconv.Atoi(item.YearPub.Value); err == nil {
			g.YearPublished = y
		}
		if n, err := strconv.Atoi(item.Stats.MinPlayers); err == nil {
			g.MinPlayers = n
		}
		if n, err := strconv.Atoi(item.Stats.MaxPlayers); err == nil {
			g.MaxPlayers = n
		}
		if w, err := strconv.ParseFloat(item.Stats.Rating.Averages.Value, 64); err == nil {
			g.Weight = w
		}
		games = append(games, g)
	}
	return games, nil
}

package handlers

import (
	"database/sql"
	"html/template"
	"net/http"
	"path/filepath"
	"runtime"

	"github.com/luismedinag/myboardgamecollection/middleware"
)

// templateDir returns the absolute path to the templates directory, located
// relative to this source file so that it works regardless of working directory.
func templateDir() string {
	_, filename, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(filename), "..", "templates")
}

func parseTemplates(names ...string) (*template.Template, error) {
	dir := templateDir()
	paths := make([]string, len(names))
	for i, n := range names {
		paths[i] = filepath.Join(dir, n)
	}
	return template.ParseFiles(paths...)
}

// IndexPage handles GET / — renders the index page with initial game list.
func IndexPage(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)

		games, _ := fetchGames(db, r, "", 1, 20)

		tmpl, err := parseTemplates("base.html", "index.html", "games.html")
		if err != nil {
			http.Error(w, "template error", http.StatusInternalServerError)
			return
		}

		data := map[string]interface{}{
			"User":  user,
			"Games": games,
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := tmpl.ExecuteTemplate(w, "base.html", data); err != nil {
			http.Error(w, "render error", http.StatusInternalServerError)
		}
	}
}

// LoginPage handles GET /login.
func LoginPage(w http.ResponseWriter, r *http.Request) {
	tmpl, err := parseTemplates("base.html", "login.html")
	if err != nil {
		http.Error(w, "template error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	tmpl.ExecuteTemplate(w, "base.html", nil) //nolint:errcheck
}

// RegisterPage handles GET /register.
func RegisterPage(w http.ResponseWriter, r *http.Request) {
	tmpl, err := parseTemplates("base.html", "register.html")
	if err != nil {
		http.Error(w, "template error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	tmpl.ExecuteTemplate(w, "base.html", nil) //nolint:errcheck
}

// HTMXGames handles GET /htmx/games — returns the games partial for HTMX.
func HTMXGames(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("q")
		games, _ := fetchGames(db, r, q, 1, 20)

		tmpl, err := parseTemplates("games.html")
		if err != nil {
			http.Error(w, "template error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		tmpl.ExecuteTemplate(w, "game-list", games) //nolint:errcheck
	}
}

// HTMXCollection handles GET /htmx/collection — returns the user's collection partial.
func HTMXCollection(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := middleware.GetUser(r)
		if user == nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		entries := fetchCollection(db, r, user.UserID)

		tmpl, err := parseTemplates("games.html")
		if err != nil {
			http.Error(w, "template error", http.StatusInternalServerError)
			return
		}

		// Build a slice of games from the collection entries for reuse of game-list partial.
		games := make([]Game, 0, len(entries))
		for _, e := range entries {
			if e.Game != nil {
				games = append(games, *e.Game)
			}
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		tmpl.ExecuteTemplate(w, "game-list", games) //nolint:errcheck
	}
}

// fetchGames is a helper shared between IndexPage and HTMXGames.
func fetchGames(db *sql.DB, r *http.Request, q string, page, perPage int) ([]Game, error) {
	pattern := "%" + q + "%"
	rows, err := db.QueryContext(r.Context(),
		`SELECT id, bgg_id, title, year_published, min_players, max_players, weight,
		        image_url, description, created_at, updated_at
		 FROM games WHERE title LIKE ?
		 ORDER BY title LIMIT ? OFFSET ?`,
		pattern, perPage, (page-1)*perPage,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	games := make([]Game, 0)
	for rows.Next() {
		var g Game
		if err := rows.Scan(
			&g.ID, &g.BGGID, &g.Title, &g.YearPublished,
			&g.MinPlayers, &g.MaxPlayers, &g.Weight,
			&g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
		); err != nil {
			return nil, err
		}
		games = append(games, g)
	}
	return games, rows.Err()
}

// fetchCollection fetches all collection entries (with embedded game) for a user.
func fetchCollection(db *sql.DB, r *http.Request, userID string) []CollectionEntry {
	rows, err := db.QueryContext(r.Context(),
		`SELECT ce.id, ce.user_id, ce.game_id, ce.status, ce.rating, ce.notes,
		        ce.created_at, ce.updated_at,
		        g.id, g.bgg_id, g.title, g.year_published, g.min_players, g.max_players,
		        g.weight, g.image_url, g.description, g.created_at, g.updated_at
		 FROM collection_entries ce
		 JOIN games g ON g.id = ce.game_id
		 WHERE ce.user_id=?
		 ORDER BY g.title`, userID,
	)
	if err != nil {
		return nil
	}
	defer rows.Close()

	entries := make([]CollectionEntry, 0)
	for rows.Next() {
		var e CollectionEntry
		var g Game
		if err := rows.Scan(
			&e.ID, &e.UserID, &e.GameID, &e.Status, &e.Rating, &e.Notes,
			&e.CreatedAt, &e.UpdatedAt,
			&g.ID, &g.BGGID, &g.Title, &g.YearPublished, &g.MinPlayers, &g.MaxPlayers,
			&g.Weight, &g.ImageURL, &g.Description, &g.CreatedAt, &g.UpdatedAt,
		); err != nil {
			continue
		}
		e.Game = &g
		entries = append(entries, e)
	}
	return entries
}

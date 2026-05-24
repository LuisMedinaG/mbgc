// Command bgg-login performs a BoardGameGeek web login and prints a Cookie header
// value suitable for the BGG_COOKIE environment variable.
//
// Usage:
//
//	ADMIN_USERNAME=you ADMIN_PASSWORD=secret go run ./cmd/bgg-login
//
// If a .env file exists in the working directory, it is loaded first (same keys as the main app).
//
// Optional: -env prints a line in the form BGG_COOKIE=... for pasting into .env
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

const (
	loginPageURL = "https://boardgamegeek.com/login/"
	loginAPIURL  = "https://boardgamegeek.com/login/api/v1"
	userAgent    = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

func main() {
	printEnv := flag.Bool("env", false, `print one line BGG_COOKIE="..." for .env files`)
	flag.Parse()

	if _, err := os.Stat(".env"); err == nil {
		if err := godotenv.Load(); err != nil {
			fmt.Fprintf(os.Stderr, "bgg-login: load .env: %v\n", err)
			os.Exit(2)
		}
	}

	user := strings.TrimSpace(os.Getenv("ADMIN_USERNAME"))
	pass := os.Getenv("ADMIN_PASSWORD")
	if user == "" || pass == "" {
		fmt.Fprintln(os.Stderr, "bgg-login: set ADMIN_USERNAME and ADMIN_PASSWORD in the environment or in .env")
		os.Exit(2)
	}

	jar, err := cookiejar.New(nil)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bgg-login: cookie jar: %v\n", err)
		os.Exit(1)
	}
	client := &http.Client{Jar: jar}

	if err := warmupSession(client); err != nil {
		fmt.Fprintf(os.Stderr, "bgg-login: warmup GET %s: %v\n", loginPageURL, err)
		os.Exit(1)
	}

	if err := doLogin(client, user, pass); err != nil {
		fmt.Fprintf(os.Stderr, "bgg-login: %v\n", err)
		os.Exit(1)
	}

	cookieHeader, err := cookieHeaderForBGG(jar)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bgg-login: %v\n", err)
		os.Exit(1)
	}

	if *printEnv {
		fmt.Printf("BGG_COOKIE=%s\n", dotEnvQuote(cookieHeader))
	} else {
		fmt.Println(cookieHeader)
	}
}

func warmupSession(client *http.Client) error {
	req, err := http.NewRequest(http.MethodGet, loginPageURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.Body.Close()
}

func doLogin(client *http.Client, username, password string) error {
	payload, err := json.Marshal(map[string]any{
		"credentials": map[string]string{
			"username": username,
			"password": password,
		},
	})
	if err != nil {
		return err
	}

	req, err := http.NewRequest(http.MethodPost, loginAPIURL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", "https://boardgamegeek.com")
	req.Header.Set("Referer", "https://boardgamegeek.com/login")
	req.Header.Set("User-Agent", userAgent)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	body, _ := io.ReadAll(resp.Body)
	if closeErr := resp.Body.Close(); closeErr != nil {
		return closeErr
	}

	if resp.StatusCode == http.StatusNoContent {
		return nil
	}

	msg := strings.TrimSpace(string(body))
	if msg == "" {
		msg = resp.Status
	}
	return fmt.Errorf("login failed (%s): %s", resp.Status, msg)
}

func cookieHeaderForBGG(jar http.CookieJar) (string, error) {
	u, err := url.Parse("https://boardgamegeek.com/")
	if err != nil {
		return "", err
	}
	cookies := jar.Cookies(u)
	if len(cookies) == 0 {
		return "", fmt.Errorf("no cookies in jar after login (unexpected)")
	}
	var b strings.Builder
	for i, c := range cookies {
		if i > 0 {
			b.WriteString("; ")
		}
		b.WriteString(c.Name)
		b.WriteByte('=')
		b.WriteString(c.Value)
	}
	return b.String(), nil
}

// dotEnvQuote wraps s in double quotes and escapes \ and " for typical .env parsers.
func dotEnvQuote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '\\', '"':
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	b.WriteByte('"')
	return b.String()
}

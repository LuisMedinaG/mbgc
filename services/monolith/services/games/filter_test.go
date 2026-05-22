package games

import "testing"

func TestPlayerCondition(t *testing.T) {
	cases := []struct {
		players string
		want    string
	}{
		{"1", "min_players <= 1"},
		{"2", "min_players <= 2"},
		{"2only", "min_players = 2 AND max_players = 2"},
		{"3", "min_players <= 3"},
		{"4", "min_players <= 4"},
		{"5plus", "max_players >= 5"},
		{"", ""},
		{"bogus", ""},
	}
	for _, c := range cases {
		got := PlayerCondition(c.players, "")
		if got != c.want {
			t.Errorf("PlayerCondition(%q) = %q, want %q", c.players, got, c.want)
		}
	}
}

func TestPlayerConditionPrefix(t *testing.T) {
	got := PlayerCondition("1", "g.")
	want := "g.min_players <= 1"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestPlaytimeCondition(t *testing.T) {
	cases := []struct {
		playtime string
		want     string
	}{
		{"short", "play_time < 30"},
		{"medium", "play_time >= 30 AND play_time <= 60"},
		{"long", "play_time > 60"},
		{"", ""},
		{"bogus", ""},
	}
	for _, c := range cases {
		got := PlaytimeCondition(c.playtime, "")
		if got != c.want {
			t.Errorf("PlaytimeCondition(%q) = %q, want %q", c.playtime, got, c.want)
		}
	}
}

func TestWeightCondition(t *testing.T) {
	cases := []struct {
		weight string
		want   string
	}{
		{"light", "weight > 0 AND weight < 2.0"},
		{"medium", "weight >= 2.0 AND weight < 3.0"},
		{"heavy", "weight >= 3.0"},
		{"", ""},
		{"bogus", ""},
	}
	for _, c := range cases {
		got := WeightCondition(c.weight, "")
		if got != c.want {
			t.Errorf("WeightCondition(%q) = %q, want %q", c.weight, got, c.want)
		}
	}
}

func TestRatingCondition(t *testing.T) {
	cases := []struct {
		rating string
		want   string
	}{
		{"good", "rating >= 6.0"},
		{"great", "rating >= 7.0"},
		{"excellent", "rating >= 8.0"},
		{"", ""},
		{"bogus", ""},
	}
	for _, c := range cases {
		got := RatingCondition(c.rating, "")
		if got != c.want {
			t.Errorf("RatingCondition(%q) = %q, want %q", c.rating, got, c.want)
		}
	}
}

func TestLanguageCondition(t *testing.T) {
	cases := []struct {
		lang string
		want string
	}{
		{"free", "language_dependence = 1"},
		{"low", "language_dependence = 2"},
		{"moderate", "language_dependence = 3"},
		{"high", "language_dependence >= 4"},
		{"", ""},
		{"bogus", ""},
	}
	for _, c := range cases {
		got := LanguageCondition(c.lang, "")
		if got != c.want {
			t.Errorf("LanguageCondition(%q) = %q, want %q", c.lang, got, c.want)
		}
	}
}

func TestRecommendedPlayersCondition(t *testing.T) {
	cases := []struct {
		count string
		want  string
	}{
		{"4", "',' || recommended_players || ',' LIKE '%,4,%'"},
		{"", ""},
		{"abc", ""},
		{"4x", ""},
	}
	for _, c := range cases {
		got := RecommendedPlayersCondition(c.count, "")
		if got != c.want {
			t.Errorf("RecommendedPlayersCondition(%q) = %q, want %q", c.count, got, c.want)
		}
	}
}

func TestRecommendedPlayersConditionPrefix(t *testing.T) {
	got := RecommendedPlayersCondition("3", "g.")
	want := "',' || g.recommended_players || ',' LIKE '%,3,%'"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

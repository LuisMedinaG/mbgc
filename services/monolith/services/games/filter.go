// Package games provides the games service: store, filter, and HTTP handlers.
package games

// PlayerCondition returns a SQL condition for the given player filter value.
// prefix is prepended to column names (e.g. "g." for aliased queries).
func PlayerCondition(players, prefix string) string {
	switch players {
	case "1":
		return prefix + "min_players <= 1"
	case "2":
		return prefix + "min_players <= 2"
	case "2only":
		return prefix + "min_players = 2 AND " + prefix + "max_players = 2"
	case "3":
		return prefix + "min_players <= 3"
	case "4":
		return prefix + "min_players <= 4"
	case "5plus":
		return prefix + "max_players >= 5"
	default:
		return ""
	}
}

// PlaytimeCondition returns a SQL condition for the given playtime filter value.
func PlaytimeCondition(playtime, prefix string) string {
	switch playtime {
	case "short":
		return prefix + "play_time < 30"
	case "medium":
		return prefix + "play_time >= 30 AND " + prefix + "play_time <= 60"
	case "long":
		return prefix + "play_time > 60"
	default:
		return ""
	}
}

// WeightCondition returns a SQL condition for the given weight filter value.
func WeightCondition(weight, prefix string) string {
	switch weight {
	case "light":
		return prefix + "weight > 0 AND " + prefix + "weight < 2.0"
	case "medium":
		return prefix + "weight >= 2.0 AND " + prefix + "weight < 3.0"
	case "heavy":
		return prefix + "weight >= 3.0"
	default:
		return ""
	}
}

// RatingCondition returns a SQL condition for the given BGG average rating filter.
func RatingCondition(rating, prefix string) string {
	switch rating {
	case "good":
		return prefix + "rating >= 6.0"
	case "great":
		return prefix + "rating >= 7.0"
	case "excellent":
		return prefix + "rating >= 8.0"
	default:
		return ""
	}
}

// LanguageCondition returns a SQL condition for the given language dependence filter.
func LanguageCondition(lang, prefix string) string {
	switch lang {
	case "free":
		return prefix + "language_dependence = 1"
	case "low":
		return prefix + "language_dependence = 2"
	case "moderate":
		return prefix + "language_dependence = 3"
	case "high":
		return prefix + "language_dependence >= 4"
	default:
		return ""
	}
}

// RecommendedPlayersCondition returns a SQL condition matching games where
// the given player count appears in the recommended_players column.
func RecommendedPlayersCondition(count, prefix string) string {
	if count == "" {
		return ""
	}
	for _, ch := range count {
		if ch < '0' || ch > '9' {
			return ""
		}
	}
	return "',' || " + prefix + "recommended_players || ',' LIKE '%," + count + ",%'"
}

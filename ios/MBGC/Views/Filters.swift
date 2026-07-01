import SwiftUI

// MARK: - Filter model — all the data types for /Filters live here.
//        Views live in FilterView.swift (kept separate so this file is small
//        enough to grok without scrolling past a wall of UI code).

enum FilterMode: String, CaseIterable, Identifiable, Codable {
    case minimum = "Minimum"
    case maximum = "Maximum"
    case exactly = "Exactly"
    case between = "Between"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .minimum: return .red
        case .maximum: return .green
        case .exactly: return .orange
        case .between: return .blue
        }
    }
}

enum FilterField: String, CaseIterable, Identifiable, Codable {
    case players       = "Players"
    case playtime      = "Playtime"
    case rating        = "Rating"
    case userRating    = "My Rating"
    case weight        = "Complexity"
    case bestFor       = "Best For"
    case bggRank       = "BGG Rank"
    case yearPublished = "Year Published"
    case timesPlayed   = "Times Played"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rating:        return "bgg-icon"
        case .userRating:    return "star.fill"
        case .weight:        return "scalemass"
        case .playtime:      return "clock"
        case .players:       return "person.2"
        case .bestFor:       return "person.2.circle"
        case .bggRank:       return "trophy"
        case .yearPublished: return "calendar"
        case .timesPlayed:   return "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .rating:        return .yellow
        case .userRating:    return .orange
        case .weight:        return .purple
        case .playtime:      return .blue
        case .players:       return .green
        case .bestFor:       return .teal
        case .bggRank:       return .yellow
        case .yearPublished: return .orange
        case .timesPlayed:   return .teal
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .rating, .userRating: return 1...10
        case .weight:              return 1...5
        case .playtime:            return 15...300
        case .players, .bestFor:   return 1...10
        case .bggRank:             return 1...5000
        case .yearPublished:       return 1970...2026
        case .timesPlayed:         return 0...200
        }
    }

    var step: Double {
        switch self {
        case .rating, .userRating: return 0.5
        case .weight:              return 0.1
        case .playtime:            return 15
        case .bggRank:             return 50
        default:                   return 1
        }
    }

    var unit: String? {
        switch self {
        case .playtime: return "min"
        case .bestFor:  return "players"
        default:        return nil
        }
    }

    var isCustomImage: Bool { self == .rating }

    var isInteger: Bool {
        switch self {
        case .playtime, .players, .bestFor, .bggRank, .yearPublished, .timesPlayed:
            return true
        default:
            return false
        }
    }

    var defaultValue: Double {
        switch self {
        case .rating, .userRating: return 7
        case .weight:              return 3
        case .playtime:            return 60
        case .players, .bestFor:   return 4
        case .bggRank:             return 1000
        case .yearPublished:       return 2015
        case .timesPlayed:         return 5
        }
    }

    var supportsBetween: Bool {
        switch self {
        case .rating, .userRating, .weight, .playtime, .bggRank, .yearPublished, .timesPlayed:
            return true
        case .players, .bestFor:
            return false
        }
    }

    func formatValue(_ v: Double) -> String {
        isInteger ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - Checklist (set-based) filter fields

enum SetFilterField: String, CaseIterable, Identifiable, Hashable, Codable {
    case designers  = "Designers"
    case artists    = "Artists"
    case publishers = "Publisher"
    case types      = "Types"
    case categories = "Categories"
    case mechanics  = "Mechanics"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .designers:  return "pencil.and.ruler"
        case .artists:    return "paintpalette"
        case .publishers: return "building.2"
        case .types:      return "square.grid.2x2"
        case .categories: return "tag"
        case .mechanics:  return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .designers:  return .cyan
        case .artists:    return .pink
        case .publishers: return .brown
        case .types:      return .indigo
        case .categories: return .teal
        case .mechanics:  return .mint
        }
    }

    func values(from games: [Game]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for game in games {
            for v in gameValues(game) { counts[v, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    func gameValues(_ game: Game) -> [String] {
        switch self {
        case .designers:  return game.designers ?? []
        case .artists:    return game.artists ?? []
        case .publishers: return game.publishers ?? []
        case .types:      return game.types ?? []
        case .categories: return game.categories ?? []
        case .mechanics:  return game.mechanics ?? []
        }
    }
}

// MARK: - Language dependence levels

struct LangLevel: Identifiable {
    let level: Int
    let title: String
    let subtitle: String
    let color: Color
    let symbol: String
    var id: Int { level }
}

let langLevels: [LangLevel] = [
    LangLevel(level: 1, title: "No necessary in-game text",  subtitle: "Can be played in any language.",                      color: .green,                               symbol: "circle"),
    LangLevel(level: 2, title: "Some necessary text",         subtitle: "Easy to recall or needs a small cheat sheet.",        color: .green,                               symbol: "triangle"),
    LangLevel(level: 3, title: "Moderate in-game text",       subtitle: "Needs a reference sheet or translated aids.",         color: Color(red: 0.75, green: 0.6, blue: 0), symbol: "diamond"),
    LangLevel(level: 4, title: "Extensive use of text",       subtitle: "Massive conversion needed to be playable.",           color: Color(red: 0.85, green: 0.45, blue: 0), symbol: "pentagon"),
    LangLevel(level: 5, title: "All in-game text necessary",  subtitle: "Unplayable in another language.",                     color: .red,                                 symbol: "hexagon"),
]

// MARK: - Unified row ordering (FilterRows)

enum FilterRowKind: Hashable, Identifiable {
    case title
    case language
    case set(SetFilterField)
    case numeric(FilterField)

    var id: Self { self }
}

// MARK: - Filter spec

struct FilterSpec: Equatable, Codable {
    var mode: FilterMode
    var value: Double
    var upperValue: Double? = nil
}

// MARK: - GameFilters

struct GameFilters: Equatable, Codable {
    var specs: [FilterField: FilterSpec] = [:]
    var setFilters: [SetFilterField: Set<String>] = [:]
    var titleContains: String = ""
    var languageLevels: Set<Int> = []

    var isEmpty: Bool { specs.isEmpty && setFilters.isEmpty && titleContains.isEmpty && languageLevels.isEmpty }
    var activeCount: Int { specs.count + setFilters.count + (titleContains.isEmpty ? 0 : 1) + (languageLevels.isEmpty ? 0 : 1) }

    func apply(_ games: [Game]) -> [Game] {
        guard !isEmpty else { return games }
        return games.filter { passes($0) }
    }

    private func passes(_ game: Game) -> Bool {
        if !titleContains.isEmpty {
            let query = titleContains.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty, !game.name.localizedCaseInsensitiveContains(query) { return false }
        }
        if !languageLevels.isEmpty {
            guard let v = game.languageDependence, languageLevels.contains(v) else { return false }
        }
        for (field, selected) in setFilters {
            if !field.gameValues(game).contains(where: { selected.contains($0) }) { return false }
        }
        for (field, spec) in specs {
            if !fieldMatches(field, spec: spec, game: game) { return false }
        }
        return true
    }

    private func fieldMatches(_ field: FilterField, spec: FilterSpec, game: Game) -> Bool {
        func check(_ v: Double) -> Bool {
            switch spec.mode {
            case .minimum: return v >= spec.value
            case .maximum: return v <= spec.value
            case .exactly: return abs(v - spec.value) < 0.001
            case .between:
                let upper = spec.upperValue ?? spec.value
                return min(spec.value, upper)...max(spec.value, upper) ~= v
            }
        }

        // Unknown values aren't filtered out — a missing field means "not enough info",
        // not "exclude". Keeps games visible when BGG lacks weight/rating/etc.
        switch field {
        case .rating:
            guard let v = game.rating else { return true }
            return check(v)
        case .userRating:
            guard let v = game.userRating else { return true }
            return check(v)
        case .weight:
            guard let v = game.weight else { return true }
            return check(v)
        case .playtime:
            guard let v = game.playtime else { return true }
            return check(Double(v))
        case .players:
            guard game.minPlayers != nil || game.maxPlayers != nil else { return true }
            let mn = Double(game.minPlayers ?? game.maxPlayers ?? 0)
            let mx = Double(game.maxPlayers ?? game.minPlayers ?? 0)
            switch spec.mode {
            case .minimum: return mx >= spec.value
            case .maximum: return mn <= spec.value
            case .exactly: return mn <= spec.value && spec.value <= mx
            case .between:
                let upper = spec.upperValue ?? spec.value
                return mn <= max(spec.value, upper) && mx >= min(spec.value, upper)
            }
        case .bestFor:
            guard let rp = game.recommendedPlayers, !rp.isEmpty else { return true }
            let n = Int(spec.value)
            switch spec.mode {
            case .minimum: return rp.contains { $0 >= n }
            case .maximum: return rp.contains { $0 <= n }
            case .exactly: return rp.contains(n)
            case .between:
                let upper = Int(spec.upperValue ?? spec.value)
                return rp.contains { min(n, upper)...max(n, upper) ~= $0 }
            }
        case .bggRank:
            // Lower rank = better. "maximum 500" → top-500 games. Unranked games pass through.
            guard let v = game.bggRank else { return true }
            return check(Double(v))
        case .yearPublished:
            guard let v = game.yearPublished else { return true }
            return check(Double(v))
        case .timesPlayed:
            guard let v = game.numberOfPlays else { return true }
            return check(Double(v))
        }
    }
}

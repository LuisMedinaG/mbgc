import Foundation
import SwiftData

// MARK: - Option

struct FinderOption: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
    var tint: String? = nil    // "#RRGGBB" background; nil = secondarySystemBackground
    var symbol: String? = nil  // SF Symbol name; nil = no icon
    var solidBg: Bool = false  // true = full-opacity bg with white text (vibe); false = pastel tint
}

// MARK: - Duration

enum DurationBucket: String, CaseIterable {
    case quick   = "Quick"
    case short   = "Short"
    case medium  = "Medium"
    case long    = "Long"
    case unknown = "Open-ended"

    var subtitle: String {
        switch self {
        case .quick:   return "Under 30 min"
        case .short:   return "30 – 60 min"
        case .medium:  return "1 – 2 hours"
        case .long:    return "2+ hours"
        case .unknown: return "No time set"
        }
    }

    func matches(_ playtime: Int?) -> Bool {
        guard let pt = playtime else { return self == .unknown }
        switch self {
        case .quick:   return pt < 30
        case .short:   return pt >= 30 && pt <= 60
        case .medium:  return pt > 60 && pt <= 120
        case .long:    return pt > 120
        case .unknown: return false
        }
    }
}

// MARK: - Question kinds
//
// Each FinderAxis case delegates to one of these. Adding a question today still
// means adding a case below + a struct here — this just gives each case's logic
// a single, self-contained home instead of spreading it across 5 switch arms.

private protocol FinderQuestionKind {
    var question: String { get }
    var usesGrid: Bool { get }
    func options(from games: [Game], collections: [Collection]) -> [FinderOption]
    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game]
    func scoreContribution(pick: FinderOption?, game: Game, weights: FinderConfig.RankingWeights) -> Double
}

private struct VibeQuestion: FinderQuestionKind {
    var question: String { "What's the vibe?" }
    var usesGrid: Bool { true }

    func options(from games: [Game], collections: [Collection]) -> [FinderOption] {
        var manualCounts: [String: Int] = [:]
        for game in games {
            for collection in game.collections where !collection.isSmart {
                manualCounts[collection.name, default: 0] += 1
            }
        }

        return collections
            .filter { !$0.isDefault }
            .compactMap { col -> FinderOption? in
                let n = col.isSmart
                    ? col.smartGames(collections: collections, allGames: games).count
                    : manualCounts[col.name, default: 0]
                guard n > 0 else { return nil }
                return FinderOption(
                    id: "vibe:\(col.name)", label: col.name, count: n,
                    tint: col.effectiveColorHex, symbol: col.effectiveIconName, solidBg: true
                )
            }
    }

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        let name = String(option.id.dropFirst("vibe:".count))
        guard let col = collections.first(where: { $0.name == name }) else { return [] }
        return col.isSmart
            ? col.smartGames(collections: collections, allGames: games)
            : games.filter { $0.collections.contains(where: { $0.name == name }) }
    }

    func scoreContribution(pick: FinderOption?, game: Game, weights: FinderConfig.RankingWeights) -> Double {
        0  // filter-only axis; picking it doesn't change individual game scores
    }
}

private struct PlayersQuestion: FinderQuestionKind {
    var question: String { "How many players tonight?" }
    var usesGrid: Bool { false }

    func options(from games: [Game], collections: [Collection]) -> [FinderOption] {
        let cap = FinderConfig.playerCap
        let tints = FinderConfig.playerTints

        // Index by player count so options are already ordered and no sort is needed.
        var gamesPerCount = Array(repeating: 0, count: cap + 1)
        for game in games {
            let lo = game.minPlayers ?? 1
            let hi = min(game.maxPlayers ?? lo, cap)
            guard lo <= hi else { continue }
            for count in lo...hi {
                gamesPerCount[count] += 1
            }
        }

        return (1...cap).compactMap { count -> FinderOption? in
            let gameCount = gamesPerCount[count]
            guard gameCount > 0 else { return nil }

            let index = count - 1
            let label = count == 1   ? "Solo"
                      : count >= cap ? "\(cap)+"
                      :                "\(count) players"
            return FinderOption(
                id: "players:\(count)",
                label: label,
                count: gameCount,
                tint: tints[min(index, tints.count - 1)]
            )
        }
    }

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        // "Supports N" — game is playable with N people when N is in its [min, max] range.
        // Games where N is the BGG-recommended count are ranked higher (see FinderFlow.ranked).
        guard let n = FinderAxis.playerCount(from: option.id) else { return games }
        return games.filter {
            let lo = $0.minPlayers ?? 1
            let hi = $0.maxPlayers ?? lo
            return lo <= n && n <= hi
        }
    }

    func scoreContribution(pick: FinderOption?, game: Game, weights: FinderConfig.RankingWeights) -> Double {
        guard let pick, let n = FinderAxis.playerCount(from: pick.id),
              game.recommendedPlayers?.contains(n) == true else { return 0 }
        return weights.recommendedPlayers
    }
}

private struct DurationQuestion: FinderQuestionKind {
    var question: String { "How much time do you have?" }
    var usesGrid: Bool { true }

    func options(from games: [Game], collections: [Collection]) -> [FinderOption] {
        var counts: [DurationBucket: Int] = [:]
        for game in games {
            let bucket: DurationBucket
            if let playtime = game.playtime {
                bucket = playtime < 30 ? .quick
                       : playtime <= 60 ? .short
                       : playtime <= 120 ? .medium
                       : .long
            } else {
                bucket = .unknown
            }
            counts[bucket, default: 0] += 1
        }

        return DurationBucket.allCases.compactMap { bucket -> FinderOption? in
            let n = counts[bucket, default: 0]
            guard n > 0 else { return nil }
            return FinderOption(id: "duration:\(bucket.rawValue)", label: bucket.rawValue,
                                count: n, tint: FinderConfig.durationTints[bucket])
        }
    }

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        let raw = String(option.id.dropFirst("duration:".count))
        guard let bucket = DurationBucket(rawValue: raw) else { return games }
        return games.filter { bucket.matches($0.playtime) }
    }

    func scoreContribution(pick: FinderOption?, game: Game, weights: FinderConfig.RankingWeights) -> Double {
        0  // filter-only axis; picking it doesn't change individual game scores
    }
}

// MARK: - Axis

// FinderAxis stays data-driven so reorder/toggle can become settings later.
enum FinderAxis: String, CaseIterable {
    case vibe, players, duration

    private var kind: FinderQuestionKind {
        switch self {
        case .vibe:     return VibeQuestion()
        case .players:  return PlayersQuestion()
        case .duration: return DurationQuestion()
        }
    }

    var question: String { kind.question }
    var usesGrid: Bool { kind.usesGrid }

    func options(from games: [Game], collections: [Collection]) -> [FinderOption] {
        kind.options(from: games, collections: collections)
    }

    func scoreContribution(pick: FinderOption?, game: Game, weights: FinderConfig.RankingWeights) -> Double {
        guard let pick, pick.id != "skip" else { return 0 }
        return kind.scoreContribution(pick: pick, game: game, weights: weights)
    }

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        guard option.id != "skip" else { return games }
        return kind.apply(option, to: games, collections: collections)
    }

    // Parses "players:N" option IDs. Single source so options(), apply(), and chosenPlayerCount agree.
    static func playerCount(from optionId: String) -> Int? {
        guard optionId.hasPrefix("players:") else { return nil }
        return Int(optionId.dropFirst("players:".count))
    }
}

// MARK: - Flow

@MainActor
@Observable
final class FinderFlow {
    let funnel = FinderConfig.funnel
    private(set) var picks: [FinderOption] = []

    var ownedGames: [Game] = []
    var allCollections: [Collection] = []

    // MARK: Derived

    var survivors: [Game] {
        var result = ownedGames
        for (i, pick) in picks.enumerated() {
            result = funnel[i].apply(pick, to: result, collections: allCollections)
        }
        return result
    }

    var stepIndex: Int { picks.count }
    var currentAxis: FinderAxis? { stepIndex < funnel.count ? funnel[stepIndex] : nil }

    var currentOptions: [FinderOption] {
        currentAxis?.options(from: survivors, collections: allCollections) ?? []
    }

    // Runs every axis. Stops when the funnel is exhausted OR the next axis produces no options
    // (e.g. all survivors share the same duration bucket — asking wouldn't split anything).
    var isDone: Bool {
        guard !ownedGames.isEmpty, stepIndex > 0 else { return false }
        return currentAxis == nil || currentOptions.isEmpty
    }

    var chosenPlayerCount: Int? {
        picks.first { $0.id.hasPrefix("players:") }
            .flatMap { FinderAxis.playerCount(from: $0.id) }
    }

    var ranked: [Game] {
        let w = FinderConfig.rankingWeights
        return survivors.sorted { a, b in
            let scoreA = rawScore(for: a, weights: w), scoreB = rawScore(for: b, weights: w)
            guard scoreA == scoreB else { return scoreA > scoreB }
            let rankA = a.bggRank ?? Int.max, rankB = b.bggRank ?? Int.max
            return rankA < rankB
        }
    }

    /// Static Game score + the sum of every picker axis' contribution for the
    /// current picks. Single source so `ranked` and `matchPercent(for:)` agree.
    private func rawScore(for game: Game, weights: FinderConfig.RankingWeights) -> Double {
        let axisContributions = funnel.enumerated().reduce(0.0) { sum, item in
            let pick = item.offset < picks.count ? picks[item.offset] : nil
            return sum + item.element.scoreContribution(pick: pick, game: game, weights: weights)
        }
        return FinderConfig.score(game) + axisContributions
    }

    var hasCollections: Bool {
        allCollections.contains(where: { !$0.isDefault })
    }

    /// 0–100 match score for a single game against the current picks.
    func matchPercent(for game: Game) -> Int {
        let w = FinderConfig.rankingWeights
        let raw = rawScore(for: game, weights: w)
        let ceiling = w.userRating + w.geekRating + w.wantToPlay + w.recommendedPlayers + w.bggRank
        let pct = ceiling > 0 ? min(max(raw / ceiling, 0), 1) : 0
        return Int((pct * 100).rounded())
    }

    // MARK: Actions

    func select(_ option: FinderOption) {
        picks.append(option)
        skipEmptySteps()
    }
    func back() { if !picks.isEmpty { picks.removeLast() } }
    func reset() { picks = [] }

    // A question with no options can't split anything — treat it as "select all"
    // (skip) and move straight to the next axis instead of stalling on an empty screen.
    // Called after ownedGames/allCollections are both in sync, and after each select().
    func skipEmptySteps() {
        while currentAxis != nil, currentOptions.isEmpty {
            picks.append(FinderOption(id: "skip", label: "Skip", count: survivors.count))
        }
    }
}

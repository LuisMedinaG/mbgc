import Foundation
import SwiftData

// MARK: - Option

/// One selectable option inside a quiz step.
/// `subtitle` shows optional secondary text under the label (used by duration buckets).
/// `tint`/`solidBg` are kept for backwards-compat with persisted data, but the UI no
/// longer reads them — every quiz option now renders through SelectableCard.
struct FinderOption: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: String? = nil
    var solidBg: Bool = false
}

// MARK: - Duration
//
// Quiz step 3 buckets aligned with the design spec:
//   Short  — under 45 min
//   Medium — 45–90 min
//   Long   — 90+ min
//   Any    — matches everything (an explicit "no constraint" option)
//
// `quick` and `unknown` are retained for backend filtering so older persisted
// game data still scores correctly, but the picker never surfaces them.

enum DurationBucket: String, CaseIterable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"
    case any = "Any"
    case quick = "Quick"      // legacy, not surfaced
    case unknown = "Open-ended"  // legacy, not surfaced

    /// Display subtitle shown under the label in the quiz card.
    var quizSubtitle: String? {
        switch self {
        case .short:  return "Under 45 min"
        case .medium: return "45 – 90 min"
        case .long:   return "90+ min"
        case .any:    return "No time constraint"
        default:      return nil
        }
    }

    func matches(_ playtime: Int?) -> Bool {
        // `any` matches everything — including unknown playtimes.
        if self == .any { return true }
        guard let pt = playtime else { return self == .unknown }
        switch self {
        case .short:  return pt < 45
        case .medium: return pt >= 45 && pt <= 90
        case .long:   return pt > 90
        case .any:    return true
        case .quick:  return pt < 30
        case .unknown: return false
        }
    }

    /// Buckets the quiz step surfaces, in display order.
    static var selectableCases: [DurationBucket] { [.short, .medium, .long, .any] }
}

// MARK: - Axis

// ponytail: funnel is [FinderAxis] array — reorder/toggle becomes a settings screen later, not a rewrite
enum FinderAxis: String, CaseIterable {
    case vibe, players, duration

    /// User-facing question title for the step header.
    var question: String {
        switch self {
        case .vibe:     return "Select a Playstyle"
        case .players:  return "Player Count"
        case .duration: return "Duration"
        }
    }

    // MARK: - Options

    func options(from games: [Game], collections: [Collection]) -> [FinderOption] {
        switch self {
        case .vibe:      return vibeOptions(games: games, collections: collections)
        case .players:   return playerOptions(games: games)
        case .duration:  return durationOptions(games: games)
        }
    }

    private func vibeOptions(games: [Game], collections: [Collection]) -> [FinderOption] {
        // Manual collections count their explicit members; smart collections count
        // the live membership computed by `smartGames`.
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
                    id: "vibe:\(col.name)",
                    label: col.name,
                    count: n,
                    symbol: col.effectiveIconName
                )
            }
            // Largest membership first → most relevant picks at the top.
            .sorted { $0.count > $1.count }
    }

    private func playerOptions(games: [Game]) -> [FinderOption] {
        let cap = FinderConfig.playerCap
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
            let label: String
            switch count {
            case 1:    label = "Solo"
            default:   label = "\(count) players"
            }
            return FinderOption(
                id: "players:\(count)",
                label: label,
                count: gameCount,
                symbol: "person.2.fill"
            )
        }
    }

    private func durationOptions(games: [Game]) -> [FinderOption] {
        // Only surface the four spec-aligned buckets. `quick` and `unknown`
        // exist for legacy filtering but are not options in the picker.
        let surfaceBuckets = DurationBucket.selectableCases
        var counts: [DurationBucket: Int] = [:]
        for bucket in surfaceBuckets { counts[bucket] = 0 }
        for game in games {
            let bucket: DurationBucket
            if let pt = game.playtime {
                bucket = pt < 45 ? .short
                       : pt <= 90 ? .medium
                       : .long
            } else {
                bucket = .any
            }
            counts[bucket, default: 0] += 1
        }
        // "Any" is always offered — the user might explicitly opt out of a time filter.
        counts[.any] = games.count

        return surfaceBuckets.compactMap { bucket -> FinderOption? in
            let n = counts[bucket, default: 0]
            guard n > 0 else { return nil }
            return FinderOption(
                id: "duration:\(bucket.rawValue)",
                label: bucket.rawValue,
                count: n,
                subtitle: bucket.quizSubtitle,
                symbol: bucket == .any ? "infinity" : "clock.fill"
            )
        }
    }

    // MARK: - Score contribution
    //
    // Each axis knows its own ranking signal. Return 0 when the pick is nil (skipped) or
    // this axis has no ranking signal (filter-only). To add a new signal: add a case here.

    func scoreContribution(pick: FinderOption?, game: Game, weights: FinderConfig.RankingWeights) -> Double {
        guard let pick, pick.id != "skip" else { return 0 }
        switch self {
        case .vibe, .duration:
            return 0  // filter-only axes; picking them doesn't change individual game scores

        case .players:
            guard let n = Self.playerCount(from: pick.id),
                  game.recommendedPlayers?.contains(n) == true else { return 0 }
            return weights.recommendedPlayers
        }
    }

    // MARK: - Apply

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        guard option.id != "skip" else { return games }
        switch self {
        case .vibe:
            let name = String(option.id.dropFirst("vibe:".count))
            guard let col = collections.first(where: { $0.name == name }) else { return [] }
            let filtered = col.isSmart
                ? col.smartGames(collections: collections, allGames: games)
                : games.filter { $0.collections.contains(where: { $0.name == name }) }
            return filtered

        case .players:
            // "Supports N" — game is playable with N people when N is in its [min, max] range.
            // Games where N is the BGG-recommended count are ranked higher (see FinderFlow.ranked).
            guard let n = Self.playerCount(from: option.id) else { return games }
            return games.filter {
                let lo = $0.minPlayers ?? 1
                let hi = $0.maxPlayers ?? lo
                return lo <= n && n <= hi
            }

        case .duration:
            let raw = String(option.id.dropFirst("duration:".count))
            guard let bucket = DurationBucket(rawValue: raw) else { return games }
            return games.filter { bucket.matches($0.playtime) }
        }
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

    /// Explanations for the "Why this match" card. The renderer collapses
    /// the labels into a sentence + a row of pills.
    var chosenPlayerLabel: String? {
        guard let count = chosenPlayerCount else { return nil }
        return count == 1 ? "Solo" : "\(count) Players"
    }

    var chosenVibeLabel: String? {
        picks.first { $0.id.hasPrefix("vibe:") }
            .map { String($0.id.dropFirst("vibe:".count)) }
    }

    var chosenDurationLabel: String? {
        picks.first { $0.id.hasPrefix("duration:") }
            .map { String($0.id.dropFirst("duration:".count)) }
    }

    /// 0–100 match score for a single game, computed against the current picks.
    /// Used in the full ranking list to display "96% match".
    func matchPercent(for game: Game) -> Int {
        // Per-axis filter pass (already done in `survivors`), so the score
        // contribution comes from the ranking signals only.
        let w = FinderConfig.rankingWeights
        let s = FinderConfig.score(game)
        let axisContribution = funnel.enumerated().reduce(0.0) { sum, item in
            let pick = item.offset < picks.count ? picks[item.offset] : nil
            return sum + item.element.scoreContribution(pick: pick, game: game, weights: w)
        }
        let raw = s + axisContribution
        // Calibrate: max realistic score is around the sum of all weights.
        let ceiling = w.userRating + w.geekRating + w.wantToPlay + w.recommendedPlayers + w.bggRank
        let pct = ceiling > 0 ? min(max(raw / ceiling, 0), 1) : 0
        return Int((pct * 100).rounded())
    }

    var ranked: [Game] {
        let w = FinderConfig.rankingWeights
        return survivors.sorted { a, b in
            let scoreA = score(a, weights: w), scoreB = score(b, weights: w)
            guard scoreA == scoreB else { return scoreA > scoreB }
            let rankA = a.bggRank ?? Int.max, rankB = b.bggRank ?? Int.max
            return rankA < rankB
        }
    }

    private func score(_ game: Game, weights: FinderConfig.RankingWeights) -> Double {
        let axisContributions = funnel.enumerated().reduce(0.0) { sum, item in
            let pick = item.offset < picks.count ? picks[item.offset] : nil
            return sum + item.element.scoreContribution(pick: pick, game: game, weights: weights)
        }
        return FinderConfig.score(game) + axisContributions
    }

    var hasCollections: Bool {
        allCollections.contains(where: { !$0.isDefault })
    }

    // MARK: Actions

    func select(_ option: FinderOption) { picks.append(option) }
    func back() { if !picks.isEmpty { picks.removeLast() } }
    func reset() { picks = [] }
}
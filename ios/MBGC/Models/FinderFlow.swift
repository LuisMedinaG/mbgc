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

// MARK: - Axis

// ponytail: funnel is [FinderAxis] array — reorder/toggle becomes a settings screen later, not a rewrite
enum FinderAxis: String, CaseIterable {
    case vibe, players, duration

    var question: String {
        switch self {
        case .vibe:     return "What's the vibe?"
        case .players:  return "How many players tonight?"
        case .duration: return "How much time do you have?"
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
        var manualCounts: [String: Int] = [:]
        for game in games {
            for collection in game.collections where !collection.isSmart {
                manualCounts[collection.name, default: 0] += 1
            }
        }

        collections
            .filter { !$0.isDefault }
            .compactMap { col in
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

    private func playerOptions(games: [Game]) -> [FinderOption] {
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

        return (1...cap).compactMap { count in
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

    private func durationOptions(games: [Game]) -> [FinderOption] {
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

        DurationBucket.allCases.compactMap { bucket in
            let n = counts[bucket, default: 0]
            guard n > 0 else { return nil }
            return FinderOption(id: "duration:\(bucket.rawValue)", label: bucket.rawValue,
                                count: n, tint: FinderConfig.durationTints[bucket])
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

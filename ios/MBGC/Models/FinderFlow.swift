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
        collections
            .filter { !$0.isDefault }
            .compactMap { col in
                let n = games.filter { $0.collections.contains(where: { $0.name == col.name }) }.count
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

        // Build a map of playerCount → number of games that support it.
        var gamesPerCount: [Int: Int] = [:]
        for game in games {
            let lo = game.minPlayers ?? 1
            let hi = min(game.maxPlayers ?? lo, cap)
            guard lo <= hi else { continue }
            for count in lo...hi {
                gamesPerCount[count, default: 0] += 1
            }
        }

        return gamesPerCount
            .sorted { $0.key < $1.key }
            .enumerated()
            .map { index, entry in
                let label = entry.key == 1     ? "Solo"
                          : entry.key >= cap   ? "\(cap)+"
                          :                     "\(entry.key) players"
                return FinderOption(
                    id: "players:\(entry.key)",
                    label: label,
                    count: entry.value,
                    tint: tints[min(index, tints.count - 1)]
                )
            }
    }

    private func durationOptions(games: [Game]) -> [FinderOption] {
        DurationBucket.allCases.compactMap { bucket in
            let n = games.filter { bucket.matches($0.playtime) }.count
            guard n > 0 else { return nil }
            return FinderOption(id: "duration:\(bucket.rawValue)", label: bucket.rawValue,
                                count: n, tint: FinderConfig.durationTints[bucket])
        }
    }

    // MARK: - Apply

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        guard option.id != "skip" else { return games }
        switch self {
        case .vibe:
            let name = String(option.id.dropFirst("vibe:".count))
            return games.filter { $0.collections.contains(where: { $0.name == name }) }

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
        let n = chosenPlayerCount
        return survivors.sorted { a, b in
            let sa = FinderConfig.score(a, players: n)
            let sb = FinderConfig.score(b, players: n)
            return sa != sb ? sa > sb : a.name < b.name
        }
    }

    var hasCollections: Bool {
        allCollections.contains(where: { !$0.isDefault })
    }

    // MARK: Actions

    func select(_ option: FinderOption) { picks.append(option) }
    func back() { if !picks.isEmpty { picks.removeLast() } }
    func reset() { picks = [] }
}

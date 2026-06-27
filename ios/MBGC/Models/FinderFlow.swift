import Foundation
import SwiftData

// MARK: - Option

struct FinderOption: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
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

    func options(from games: [Game], collections: [Collection]) -> [FinderOption] {
        switch self {
        case .vibe:
            return collections
                .filter { !$0.isDefault }
                .compactMap { col in
                    let n = games.filter { $0.collections.contains(where: { $0.name == col.name }) }.count
                    guard n > 0 else { return nil }
                    return FinderOption(id: "vibe:\(col.name)", label: col.name, count: n)
                }

        case .players:
            var freq: [Int: Int] = [:]
            for g in games {
                let lo = g.minPlayers ?? 1
                let hi = min(g.maxPlayers ?? lo, 10)
                guard lo <= hi else { continue }
                for n in lo...hi { freq[n, default: 0] += 1 }
            }
            return freq.sorted { $0.key < $1.key }.map { n, c in
                let label = n >= 10 ? "10+" : n == 1 ? "1 player" : "\(n) players"
                return FinderOption(id: "players:\(n)", label: label, count: c)
            }

        case .duration:
            return DurationBucket.allCases.compactMap { bucket in
                let n = games.filter { bucket.matches($0.playtime) }.count
                guard n > 0 else { return nil }
                return FinderOption(id: "duration:\(bucket.rawValue)", label: bucket.rawValue, count: n)
            }
        }
    }

    func apply(_ option: FinderOption, to games: [Game], collections: [Collection]) -> [Game] {
        switch self {
        case .vibe:
            let name = option.id.replacingOccurrences(of: "vibe:", with: "")
            return games.filter { $0.collections.contains(where: { $0.name == name }) }

        case .players:
            guard let n = Int(option.id.replacingOccurrences(of: "players:", with: "")) else { return games }
            return games.filter {
                let lo = $0.minPlayers ?? 1
                let hi = $0.maxPlayers ?? lo
                return lo <= n && n <= hi
            }

        case .duration:
            let raw = option.id.replacingOccurrences(of: "duration:", with: "")
            guard let bucket = DurationBucket(rawValue: raw) else { return games }
            return games.filter { bucket.matches($0.playtime) }
        }
    }
}

// MARK: - Flow

@MainActor
@Observable
final class FinderFlow {
    // ponytail: fixed funnel — future settings screen swaps this array, no other changes needed
    let funnel: [FinderAxis] = [.vibe, .players, .duration]
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

    // Early stop: ≤3 survivors, funnel exhausted, or next axis can't split the pool
    var isDone: Bool {
        guard !ownedGames.isEmpty else { return false }
        return survivors.count <= 3 || currentAxis == nil || currentOptions.count <= 1
    }

    var chosenPlayerCount: Int? {
        picks.first { $0.id.hasPrefix("players:") }
            .flatMap { Int($0.id.replacingOccurrences(of: "players:", with: "")) }
    }

    // ponytail: ranking chain is data — future: persist a different order for configurability
    var ranked: [Game] {
        let n = chosenPlayerCount
        return survivors.sorted { a, b in
            let ra = a.rating ?? 0, rb = b.rating ?? 0
            if ra != rb { return ra > rb }
            if let n {
                let af = a.recommendedPlayers?.contains(n) == true
                let bf = b.recommendedPlayers?.contains(n) == true
                if af != bf { return af }
            }
            return a.name < b.name
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

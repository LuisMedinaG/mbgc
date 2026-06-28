import Foundation
import SwiftData

/// SwiftData model for a named group of games (e.g. "Library", user-defined vibes).
/// Library is the default collection — present on every device, cannot be deleted.
@Model
final class Collection {
    var name: String = ""
    var desc: String = ""
    /// true = Library (default, cannot be deleted)
    var isDefault: Bool = false
    var createdAt: Date = Date()
    var colorHex: String = ""   // "#RRGGBB"; empty = derive from name hash
    var iconName: String = ""   // SF Symbol name; empty = derive from name hash

    /// Stable identifier used for referencing this collection in smart-list rules.
    /// This ensures rules remain valid even if the collection is renamed.
    var id: UUID = UUID()

    /// Indicates if this is a "smart" collection whose membership is dynamically
    /// computed based on rules rather than manual assignment.
    var isSmart: Bool = false

    /// Persisted JSON data for the `SmartRule` defining this collection's membership.
    var ruleData: Data?

    /// Manually-curated games in this collection.
    /// For smart collections, this property remains empty and `smartGames()` should be used.
    @Relationship(deleteRule: .nullify, inverse: \Game.collections)
    var games: [Game] = []

    // ponytail: append-only — indices must stay stable; colorPalette[i] must always map to same color
    static let colorPalette: [String] = [
        "#C8622A", // terracotta
        "#C8921C", // amber
        "#4E8E44", // forest
        "#B83860", // berry
        "#3A6EA8", // ocean
        "#A05C2C", // cedar
        "#7A9438", // olive
        "#6A449A", // plum
        "#268A82", // teal
        "#8A4840", // rust
    ]
    static let iconPalette: [String] = [
        "star.fill", "flame.fill", "bolt.fill", "heart.fill", "leaf.fill",
        "crown.fill", "gamecontroller.fill", "dice.fill", "person.3.fill", "trophy.fill",
    ]

    /// The color hex to use for UI display. If `colorHex` is empty, it returns
    /// a stable fallback derived from the collection's name.
    var effectiveColorHex: String {
        colorHex.isEmpty
            ? Collection.colorPalette[abs(name.hashValue) % Collection.colorPalette.count]
            : colorHex
    }
    /// The SF Symbol name to use for UI display. If `iconName` is empty, it returns
    /// a stable fallback derived from the collection's name.
    var effectiveIconName: String {
        iconName.isEmpty
            ? Collection.iconPalette[abs(name.hashValue) % Collection.iconPalette.count]
            : iconName
    }

    init(name: String, desc: String = "", isDefault: Bool = false) {
        self.name = name
        self.desc = desc
        self.isDefault = isDefault
        self.createdAt = isDefault ? Date.distantPast : Date() // distantPast sorts Library before all user collections
        if !isDefault {
            colorHex = Collection.colorPalette[Int.random(in: 0..<Collection.colorPalette.count)]
            iconName  = Collection.iconPalette[Int.random(in: 0..<Collection.iconPalette.count)]
        }
    }
}

// MARK: - Smart lists

/// Rules that derive a smart list's membership. Persisted as JSON in `Collection.ruleData`.
/// Lists are referenced by `Collection.id` so renames don't break a rule.
struct SmartRule: Codable, Equatable {
    var combine:   [UUID] = []   // union of these lists — the base set (empty = all games)
    var intersect: [UUID] = []   // keep only games present in ALL of these
    var subtract:  [UUID] = []   // remove games present in ANY of these (A \ B)
    // ponytail: exclude = symmetric difference (games in exactly one side), distinct from
    // subtract to match the 4 screenshot rows. Drop it + its UI row to collapse to 3 ops.
    var exclude:   [UUID] = []
    var filters:   GameFilters = .init()

    var isEmpty: Bool {
        combine.isEmpty && intersect.isEmpty && subtract.isEmpty && exclude.isEmpty && filters.isEmpty
    }
}

extension Collection {
    var decodedRule: SmartRule? {
        guard let ruleData else { return nil }
        return try? JSONDecoder().decode(SmartRule.self, from: ruleData)
    }

    func setRule(_ rule: SmartRule) {
        ruleData = try? JSONEncoder().encode(rule)
    }

    /// Computes a smart list's membership on demand. Pure — no DB writes.
    /// Resolves only direct membership: a referenced smart list contributes its
    /// stored `games` (empty), not its computed set (no transitive resolution).
    func smartGames(collections: [Collection], allGames: [Game]) -> [Game] {
        guard isSmart, let rule = decodedRule else { return [] }
        let byId = Dictionary(collections.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func ids(_ list: [UUID]) -> [Set<Int>] {
            list.compactMap { byId[$0] }.map { Set($0.games.map(\.bggId)) }
        }

        // Base: union of combine lists; empty combine = every game.
        var base: Set<Int>
        let combineSets = ids(rule.combine)
        if combineSets.isEmpty {
            base = Set(allGames.map(\.bggId))
        } else {
            base = combineSets.reduce(into: Set<Int>()) { $0.formUnion($1) }
        }

        // Intersect: keep only games present in every intersect list.
        for set in ids(rule.intersect) { base.formIntersection(set) }

        // Subtract: remove games present in any subtract list.
        for set in ids(rule.subtract) { base.subtract(set) }

        // Exclude: symmetric difference against each exclude list.
        for set in ids(rule.exclude) { base.formSymmetricDifference(set) }

        let members = allGames.filter { base.contains($0.bggId) }
        return rule.filters.apply(members)
    }
}

/// Namespace for local SwiftData operations shared across import flows.
@MainActor
enum LocalLibrary {
    /// Fetches the Library collection or creates it on first launch.
    static func ensureDefaultCollection(in modelContext: ModelContext) throws -> Collection {
        let all = try modelContext.fetch(FetchDescriptor<Collection>())
        if let library = all.first(where: { $0.isDefault }) {
            return library
        }

        let library = Collection(name: "Library", isDefault: true)
        modelContext.insert(library)
        return library
    }

    static func existingBggIds(in modelContext: ModelContext, from ids: [Int]) -> Set<Int> {
        let idSet = Set(ids)
        let all = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        return Set(all.map(\.bggId).filter { idSet.contains($0) })
    }

    /// Local Game objects whose bggId is in `ids` — for routing an imported set to a collection.
    static func games(matching ids: [Int], in modelContext: ModelContext) -> [Game] {
        let idSet = Set(ids)
        let all = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        return all.filter { idSet.contains($0.bggId) }
    }

    static func add(_ games: [Game], to collection: Collection) {
        let existing = Set(collection.games.map(\.bggId)) // skip games already in the collection
        collection.games.append(contentsOf: games.filter { !existing.contains($0.bggId) })
    }
}

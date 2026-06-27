import Foundation
import SwiftData

@Model
final class Collection {
    var name: String = ""
    var desc: String = ""
    /// true = Library (default, cannot be deleted)
    var isDefault: Bool = false
    var createdAt: Date = Date()
    var colorHex: String = ""   // "#RRGGBB"; empty = derive from name hash
    var iconName: String = ""   // SF Symbol name; empty = derive from name hash

    /// Games in this collection — populated via the inverse Game.collections relationship.
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

    var effectiveColorHex: String {
        colorHex.isEmpty
            ? Collection.colorPalette[abs(name.hashValue) % Collection.colorPalette.count]
            : colorHex
    }
    var effectiveIconName: String {
        iconName.isEmpty
            ? Collection.iconPalette[abs(name.hashValue) % Collection.iconPalette.count]
            : iconName
    }

    init(name: String, desc: String = "", isDefault: Bool = false) {
        self.name = name
        self.desc = desc
        self.isDefault = isDefault
        self.createdAt = isDefault ? Date.distantPast : Date()
        if !isDefault {
            colorHex = Collection.colorPalette[Int.random(in: 0..<Collection.colorPalette.count)]
            iconName  = Collection.iconPalette[Int.random(in: 0..<Collection.iconPalette.count)]
        }
    }
}

@MainActor
enum LocalLibrary {
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
        let existing = Set(collection.games.map(\.bggId))
        collection.games.append(contentsOf: games.filter { !existing.contains($0.bggId) })
    }
}

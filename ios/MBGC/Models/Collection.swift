import Foundation
import SwiftData

@Model
final class Collection {
    var name: String = ""
    var desc: String = ""
    /// true = Library (default, cannot be deleted)
    var isDefault: Bool = false
    var createdAt: Date = Date()

    /// Games in this collection — populated via the inverse Game.collections relationship.
    @Relationship(deleteRule: .nullify, inverse: \Game.collections)
    var games: [Game] = []

    init(name: String, desc: String = "", isDefault: Bool = false) {
        self.name = name
        self.desc = desc
        self.isDefault = isDefault
        self.createdAt = isDefault ? Date.distantPast : Date()
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

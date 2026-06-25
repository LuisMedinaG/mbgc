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

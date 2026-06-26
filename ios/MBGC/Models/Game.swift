import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var bggId: Int = 0
    var name: String = ""
    var yearPublished: Int?
    var thumbnail: String?
    var image: String?
    var minPlayers: Int?
    var maxPlayers: Int?
    var playtime: Int?
    var rulesUrl: String?
    var gameDescription: String?
    var categories: [String]?
    var mechanics: [String]?
    var types: [String]?
    var weight: Double?
    var rating: Double?
    var languageDependence: Int?
    var recommendedPlayers: [Int]?

    /// Local SwiftData collections this game belongs to (e.g. Library, user vibes).
    var collections: [Collection] = []

    init(bggGame: BGGGame) {
        bggId = bggGame.bggId
        apply(bggGame)
    }

    func update(from bggGame: BGGGame) {
        apply(bggGame)
    }

    private func apply(_ bggGame: BGGGame) {
        name = bggGame.name
        yearPublished = bggGame.yearPublished > 0 ? bggGame.yearPublished : nil
        thumbnail = bggGame.thumbnail.isEmpty ? nil : bggGame.thumbnail
        image = bggGame.image.isEmpty ? nil : bggGame.image
        minPlayers = bggGame.minPlayers > 0 ? bggGame.minPlayers : nil
        maxPlayers = bggGame.maxPlayers > 0 ? bggGame.maxPlayers : nil
        playtime = bggGame.playTime > 0 ? bggGame.playTime : nil
        gameDescription = bggGame.description.isEmpty ? nil : bggGame.description
        categories = bggGame.categories.isEmpty ? nil : bggGame.categories
        mechanics = bggGame.mechanics.isEmpty ? nil : bggGame.mechanics
        types = bggGame.types.isEmpty ? nil : bggGame.types
        weight = bggGame.weight > 0 ? bggGame.weight : nil
        rating = bggGame.rating > 0 ? bggGame.rating : nil
        languageDependence = bggGame.languageDependence > 0 ? bggGame.languageDependence : nil
        recommendedPlayers = bggGame.recommendedPlayers.isEmpty ? nil : bggGame.recommendedPlayers
    }
}

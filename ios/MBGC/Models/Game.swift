import Foundation
import SwiftData

/// SwiftData model for a board game imported from BGG.
/// `bggId` is the unique key; duplicate imports update the existing record instead of creating a new one.
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
    var geekRating: Double?
    var bggRank: Int?
    var userRating: Double?
    var wantToPlay: Bool = false
    var numberOfPlays: Int?
    var lastLogPlayed: Date?  // ponytail: local-only, nil until play logging is built
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

    // BGG encodes missing integers as 0 and missing strings as ""; convert to nil so optionals stay meaningful.
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
        geekRating = bggGame.geekRating > 0 ? bggGame.geekRating : nil
        bggRank = bggGame.bggRank > 0 ? bggGame.bggRank : nil
        userRating = bggGame.userRating > 0 ? bggGame.userRating : nil
        wantToPlay = bggGame.wantToPlay
        numberOfPlays = bggGame.numberOfPlays > 0 ? bggGame.numberOfPlays : nil
        languageDependence = bggGame.languageDependence > 0 ? bggGame.languageDependence : nil
        recommendedPlayers = bggGame.recommendedPlayers.isEmpty ? nil : bggGame.recommendedPlayers
    }
}

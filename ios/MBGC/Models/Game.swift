import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var id: Int
    var bggId: Int?
    var name: String
    var yearPublished: Int?
    var thumbnail: String?
    var image: String?
    var minPlayers: Int?
    var maxPlayers: Int?
    var playtime: Int?
    var rulesUrl: String?
    var gameDescription: String
    var categories: [String]
    var mechanics: [String]
    var types: [String]
    var weight: Double
    var rating: Double
    var languageDependence: Int
    var recommendedPlayers: [Int]
    var vibeNames: [String]
    var vibeCollectionIds: [Int]

    init(dto: GameDTO) {
        id = dto.id
        bggId = dto.bggId
        name = dto.name
        yearPublished = dto.yearPublished
        thumbnail = dto.thumbnail
        image = dto.image
        minPlayers = dto.minPlayers
        maxPlayers = dto.maxPlayers
        playtime = dto.playtime
        rulesUrl = dto.rulesUrl
        gameDescription = dto.description
        categories = dto.categories
        mechanics = dto.mechanics
        types = dto.types
        weight = dto.weight
        rating = dto.rating
        languageDependence = dto.languageDependence
        recommendedPlayers = dto.recommendedPlayers
        vibeNames = dto.vibes.map(\.name)
        vibeCollectionIds = dto.vibes.map(\.id)
    }

    init(detailDTO: GameDetailDTO) {
        id = detailDTO.id
        bggId = detailDTO.bggId
        name = detailDTO.name
        yearPublished = detailDTO.yearPublished
        thumbnail = detailDTO.thumbnail
        image = detailDTO.image
        minPlayers = detailDTO.minPlayers
        maxPlayers = detailDTO.maxPlayers
        playtime = detailDTO.playtime
        rulesUrl = detailDTO.rulesUrl
        gameDescription = detailDTO.description
        categories = detailDTO.categories
        mechanics = detailDTO.mechanics
        types = detailDTO.types
        weight = detailDTO.weight
        rating = detailDTO.rating
        languageDependence = detailDTO.languageDependence
        recommendedPlayers = detailDTO.recommendedPlayers
        vibeNames = detailDTO.vibes.map(\.name)
        vibeCollectionIds = detailDTO.vibes.map(\.id)
    }

    func update(from dto: GameDTO) {
        bggId = dto.bggId
        name = dto.name
        yearPublished = dto.yearPublished
        thumbnail = dto.thumbnail
        image = dto.image
        minPlayers = dto.minPlayers
        maxPlayers = dto.maxPlayers
        playtime = dto.playtime
        rulesUrl = dto.rulesUrl
        gameDescription = dto.description
        categories = dto.categories
        mechanics = dto.mechanics
        types = dto.types
        weight = dto.weight
        rating = dto.rating
        languageDependence = dto.languageDependence
        recommendedPlayers = dto.recommendedPlayers
        vibeNames = dto.vibes.map(\.name)
        vibeCollectionIds = dto.vibes.map(\.id)
    }

    func update(from dto: GameDetailDTO) {
        bggId = dto.bggId
        name = dto.name
        yearPublished = dto.yearPublished
        thumbnail = dto.thumbnail
        image = dto.image
        minPlayers = dto.minPlayers
        maxPlayers = dto.maxPlayers
        playtime = dto.playtime
        rulesUrl = dto.rulesUrl
        gameDescription = dto.description
        categories = dto.categories
        mechanics = dto.mechanics
        types = dto.types
        weight = dto.weight
        rating = dto.rating
        languageDependence = dto.languageDependence
        recommendedPlayers = dto.recommendedPlayers
        vibeNames = dto.vibes.map(\.name)
        vibeCollectionIds = dto.vibes.map(\.id)
    }
}

struct GameDTO: Decodable, Identifiable {
    let id: Int
    let bggId: Int?
    let name: String
    let yearPublished: Int?
    let thumbnail: String?
    let image: String?
    let minPlayers: Int?
    let maxPlayers: Int?
    let playtime: Int?
    let rulesUrl: String?
    let description: String
    let categories: [String]
    let mechanics: [String]
    let types: [String]
    let weight: Double
    let rating: Double
    let languageDependence: Int
    let recommendedPlayers: [Int]
    let vibes: [VibeRefDTO]
}

struct GameDetailDTO: Decodable, Identifiable {
    let id: Int
    let bggId: Int?
    let name: String
    let yearPublished: Int?
    let thumbnail: String?
    let image: String?
    let minPlayers: Int?
    let maxPlayers: Int?
    let playtime: Int?
    let rulesUrl: String?
    let description: String
    let categories: [String]
    let mechanics: [String]
    let types: [String]
    let weight: Double
    let rating: Double
    let languageDependence: Int
    let recommendedPlayers: [Int]
    let vibes: [VibeRefDTO]
    // ponytail: no player_aids in detail for now
}

struct VibeRefDTO: Decodable {
    let id: Int
    let name: String
}

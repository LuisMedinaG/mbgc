import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var id: Int = 0
    var bggId: Int?
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
    var vibeNames: [String] = []
    var vibeCollectionIds: [Int]?

    init(dto: GameDTO) {
        id = dto.id
        apply(dto)
    }

    func update(from dto: GameDTO) {
        apply(dto)
    }

    private func apply(_ dto: GameDTO) {
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

// Mirrors services/api/internal/catalog/model.go Game — fields without
// `omitempty` in the Go struct are always present (default to empty), the
// rest are omitted entirely when nil, never sent as JSON null.
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
    let description: String?
    let categories: [String]
    let mechanics: [String]
    let types: [String]
    let weight: Double?
    let rating: Double?
    let languageDependence: Int?
    let recommendedPlayers: [Int]
    let vibes: [VibeRefDTO]
    // ponytail: no player_aids in detail for now

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        bggId = try c.decodeIfPresent(Int.self, forKey: .bggId)
        name = try c.decode(String.self, forKey: .name)
        yearPublished = try c.decodeIfPresent(Int.self, forKey: .yearPublished)
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        minPlayers = try c.decodeIfPresent(Int.self, forKey: .minPlayers)
        maxPlayers = try c.decodeIfPresent(Int.self, forKey: .maxPlayers)
        playtime = try c.decodeIfPresent(Int.self, forKey: .playtime)
        rulesUrl = try c.decodeIfPresent(String.self, forKey: .rulesUrl)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        mechanics = try c.decodeIfPresent([String].self, forKey: .mechanics) ?? []
        types = try c.decodeIfPresent([String].self, forKey: .types) ?? []
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        languageDependence = try c.decodeIfPresent(Int.self, forKey: .languageDependence)
        recommendedPlayers = try c.decodeIfPresent([Int].self, forKey: .recommendedPlayers) ?? []
        vibes = try c.decodeIfPresent([VibeRefDTO].self, forKey: .vibes) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, bggId, name, yearPublished, thumbnail, image, minPlayers, maxPlayers
        case playtime, rulesUrl, description, categories, mechanics, types, weight, rating
        case languageDependence, recommendedPlayers, vibes
    }

    // Mirrors a cached Game for an instant first render while the network
    // refresh in GameDetailViewModel.load is still in flight.
    init(game: Game) {
        id = game.id
        bggId = game.bggId
        name = game.name
        yearPublished = game.yearPublished
        thumbnail = game.thumbnail
        image = game.image
        minPlayers = game.minPlayers
        maxPlayers = game.maxPlayers
        playtime = game.playtime
        rulesUrl = game.rulesUrl
        description = game.gameDescription
        categories = game.categories ?? []
        mechanics = game.mechanics ?? []
        types = game.types ?? []
        weight = game.weight
        rating = game.rating
        languageDependence = game.languageDependence
        recommendedPlayers = game.recommendedPlayers ?? []
        vibes = zip(game.vibeCollectionIds ?? [], game.vibeNames).map { VibeRefDTO(id: $0, name: $1) }
    }
}

// services/api returns the same shape for list and detail responses.
typealias GameDetailDTO = GameDTO

struct VibeRefDTO: Decodable {
    let id: Int
    let name: String
}

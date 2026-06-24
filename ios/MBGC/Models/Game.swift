import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var id: Int
    var bggId: Int?
    var name: String
    var yearPublished: Int?
    var thumbnail: String?
    var minPlayers: Int?
    var maxPlayers: Int?
    var playtime: Int?
    var rulesUrl: String?
    var vibeNames: [String]

    init(dto: GameDTO) {
        id = dto.id
        bggId = dto.bggId
        name = dto.name
        yearPublished = dto.yearPublished
        thumbnail = dto.thumbnail
        minPlayers = dto.minPlayers
        maxPlayers = dto.maxPlayers
        playtime = dto.playtime
        rulesUrl = dto.rulesUrl
        vibeNames = dto.vibes.map(\.name)
    }

    func update(from dto: GameDTO) {
        bggId = dto.bggId
        name = dto.name
        yearPublished = dto.yearPublished
        thumbnail = dto.thumbnail
        minPlayers = dto.minPlayers
        maxPlayers = dto.maxPlayers
        playtime = dto.playtime
        rulesUrl = dto.rulesUrl
        vibeNames = dto.vibes.map(\.name)
    }
}

// ponytail: only fields the Library/Search screens render. Add description, image,
// categories, mechanics, weight, rating etc. when GameDetailView needs them.
struct GameDTO: Decodable, Identifiable {
    let id: Int
    let bggId: Int?
    let name: String
    let yearPublished: Int?
    let thumbnail: String?
    let minPlayers: Int?
    let maxPlayers: Int?
    let playtime: Int?
    let rulesUrl: String?
    let vibes: [VibeRefDTO]
}

struct VibeRefDTO: Decodable {
    let id: Int
    let name: String
}

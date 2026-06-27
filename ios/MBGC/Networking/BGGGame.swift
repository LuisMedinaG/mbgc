import Foundation

struct BGGGame: Sendable {
    let bggId: Int
    let name: String
    let description: String
    let yearPublished: Int
    let image: String
    let thumbnail: String
    let minPlayers: Int
    let maxPlayers: Int
    let playTime: Int
    let categories: [String]
    let mechanics: [String]
    let types: [String]
    let weight: Double
    let rating: Double
    let geekRating: Double
    let bggRank: Int
    var userRating: Double
    var wantToPlay: Bool
    var numberOfPlays: Int
    let languageDependence: Int
    let recommendedPlayers: [Int]
}

import Foundation

struct Collection: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let gameCount: Int
}

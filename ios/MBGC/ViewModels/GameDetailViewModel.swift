import Foundation
import SwiftData

@MainActor
@Observable
final class GameDetailViewModel {
    var game: Game?
    var errorMessage: String?

    func load(gameId: Int, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.bggId == gameId })
        game = try? modelContext.fetch(descriptor).first
        if game == nil { errorMessage = "Game not found in local library." }
    }
}

import Foundation
import SwiftData

@MainActor
@Observable
final class LibraryViewModel {
    var isLoading = false
    var errorMessage: String?
    var loadProgress: (loaded: Int, total: Int)?

    func refresh(modelContext: ModelContext) async {
        errorMessage = nil
        isLoading = true
        loadProgress = nil
        defer { isLoading = false; loadProgress = nil }
        do {
            let dtos = try await APIClient.shared.listGames(onPage: { @MainActor [weak self] loaded, total in
                self?.loadProgress = (loaded, total)
            })
            let existing = try modelContext.fetch(FetchDescriptor<Game>())
            var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.bggId, $0) })

            for dto in dtos {
                if let game = byId.removeValue(forKey: dto.id) {
                    game.update(from: dto)
                } else {
                    modelContext.insert(Game(dto: dto))
                }
            }
            for stale in byId.values {
                modelContext.delete(stale)
            }
            try modelContext.save()
        } catch {
            errorMessage = "Couldn't refresh your library."
        }
    }
}

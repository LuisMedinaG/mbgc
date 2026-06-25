import Foundation
import SwiftData

@MainActor
@Observable
final class GameDetailViewModel {
    var game: GameDetailDTO?
    var collections: [CollectionDTO] = []
    var selectedVibeIds: Set<Int> = []
    var isLoading = false
    var isSaving = false
    var isDeleting = false
    var errorMessage: String?
    var showDeleteConfirm = false
    var editingVibes = false

    func load(gameId: Int, modelContext: ModelContext) async {
        errorMessage = nil
        // ponytail: render the cached copy instantly, then refresh from the
        // network — mirrors LibraryView's cache-first read.
        if let cached = fetchLocalGame(gameId: gameId, modelContext: modelContext) {
            game = GameDTO(game: cached)
        } else {
            isLoading = true
        }
        defer { isLoading = false }
        do {
            async let gameTask = APIClient.shared.getGame(id: gameId)
            async let collectionsTask = APIClient.shared.listCollections()
            let (g, c) = try await (gameTask, collectionsTask)
            game = g
            collections = c
            selectedVibeIds = Set(g.vibes.map(\.id))
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't load game."
        }
    }

    func saveVibes(gameId: Int, modelContext: ModelContext) async {
        guard game != nil else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await APIClient.shared.setGameCollections(gameId: gameId, collectionIds: Array(selectedVibeIds))
            editingVibes = false
            // ponytail: refetch game to update local SwiftData
            if let updated = try? await APIClient.shared.getGame(id: gameId) {
                self.game = updated
                if let localGame = fetchLocalGame(gameId: gameId, modelContext: modelContext) {
                    localGame.update(from: updated)
                    try? modelContext.save()
                }
            }
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't save vibes."
        }
    }

    func updateRulesUrl(gameId: Int, modelContext: ModelContext) async {
        guard let game, let rulesUrl = game.rulesUrl else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await APIClient.shared.updateRulesUrl(gameId: gameId, rulesUrl: rulesUrl)
            if let localGame = fetchLocalGame(gameId: gameId, modelContext: modelContext) {
                localGame.rulesUrl = rulesUrl
                try? modelContext.save()
            }
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't update rules URL."
        }
    }

    func deleteGame(gameId: Int, modelContext: ModelContext) async -> Bool {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await APIClient.shared.deleteGame(id: gameId)
            if let localGame = fetchLocalGame(gameId: gameId, modelContext: modelContext) {
                modelContext.delete(localGame)
                try? modelContext.save()
            }
            return true
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't delete game."
        }
        return false
    }

    func toggleVibe(_ id: Int) {
        if selectedVibeIds.contains(id) {
            selectedVibeIds.remove(id)
        } else {
            selectedVibeIds.insert(id)
        }
    }

    func startEditingVibes() {
        if let game {
            selectedVibeIds = Set(game.vibes.map(\.id))
        }
        editingVibes = true
    }

    private func fetchLocalGame(gameId: Int, modelContext: ModelContext) -> Game? {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.bggId == gameId })
        return try? modelContext.fetch(descriptor).first
    }
}

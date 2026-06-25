import Foundation
import SwiftData

@MainActor
@Observable
final class GameDetailViewModel {
    var game: Game?
    var selectedCollectionIds: Set<PersistentIdentifier> = []
    var isSaving = false
    var isDeleting = false
    var errorMessage: String?
    var showDeleteConfirm = false
    var editingCollections = false

    func load(gameId: Int, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.bggId == gameId })
        game = try? modelContext.fetch(descriptor).first
        if game == nil { errorMessage = "Game not found in local library." }
    }

    func startEditingCollections() {
        selectedCollectionIds = Set(game?.collections.map(\.persistentModelID) ?? [])
        editingCollections = true
    }

    func toggleCollection(_ col: Collection) {
        if selectedCollectionIds.contains(col.persistentModelID) {
            selectedCollectionIds.remove(col.persistentModelID)
        } else {
            selectedCollectionIds.insert(col.persistentModelID)
        }
    }

    func saveCollections(allCollections: [Collection], modelContext: ModelContext) {
        guard let game else { return }
        isSaving = true
        game.collections = allCollections.filter { selectedCollectionIds.contains($0.persistentModelID) }
        try? modelContext.save()
        editingCollections = false
        isSaving = false
    }

    func updateRulesUrl(_ url: String, modelContext: ModelContext) {
        game?.rulesUrl = url
        try? modelContext.save()
    }

    func deleteGame(modelContext: ModelContext) -> Bool {
        guard let game else { return false }
        isDeleting = true
        modelContext.delete(game)
        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Couldn't delete game."
            isDeleting = false
            return false
        }
    }
}

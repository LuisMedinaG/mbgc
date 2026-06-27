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
        guard !col.isDefault else { return }
        if selectedCollectionIds.contains(col.persistentModelID) {
            selectedCollectionIds.remove(col.persistentModelID)
        } else {
            selectedCollectionIds.insert(col.persistentModelID)
        }
    }

    func saveCollections(allCollections: [Collection], modelContext: ModelContext) {
        guard let game else { return }
        isSaving = true
        defer { isSaving = false }
        game.collections = allCollections.filter { $0.isDefault || selectedCollectionIds.contains($0.persistentModelID) }
        do {
            try modelContext.save()
            editingCollections = false
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save collections."
        }
    }

    func updateRulesUrl(_ url: String, modelContext: ModelContext) {
        game?.rulesUrl = url
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save rules URL."
        }
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

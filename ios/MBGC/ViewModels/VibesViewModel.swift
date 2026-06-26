import Foundation
import SwiftData

@MainActor
@Observable
final class VibesViewModel {
    var errorMessage: String?

    // Collections are driven by @Query in VibesView — no local array needed.

    func create(name: String, description: String, modelContext: ModelContext) {
        let col = Collection(name: name, desc: description)
        modelContext.insert(col)
        save(modelContext)
    }

    func update(_ collection: Collection, name: String, description: String, modelContext: ModelContext) {
        collection.name = name
        collection.desc = description
        save(modelContext)
    }

    func delete(_ collection: Collection, modelContext: ModelContext) {
        guard !collection.isDefault else { return }
        modelContext.delete(collection)
        save(modelContext)
    }

    private func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

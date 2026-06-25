import Foundation

@MainActor
@Observable
final class VibesViewModel {
    var collections: [Collection] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            collections = try await APIClient.shared.listCollections()
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't load vibes."
        }
    }

    func create(name: String, description: String) async {
        errorMessage = nil
        do {
            let col = try await APIClient.shared.createCollection(name: name, description: description)
            collections.append(col)
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't create vibe."
        }
    }

    func update(_ collection: Collection, name: String, description: String) async {
        errorMessage = nil
        do {
            try await APIClient.shared.updateCollection(id: collection.id, name: name, description: description)
            if let idx = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[idx] = Collection(id: collection.id, name: name, description: description, gameCount: collection.gameCount)
            }
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't update vibe."
        }
    }

    func delete(_ collection: Collection) async {
        errorMessage = nil
        collections.removeAll { $0.id == collection.id }
        do {
            try await APIClient.shared.deleteCollection(id: collection.id)
        } catch APIError.server(_, let message) {
            errorMessage = message
            await load()
        } catch {
            errorMessage = "Couldn't delete vibe."
            await load()
        }
    }
}

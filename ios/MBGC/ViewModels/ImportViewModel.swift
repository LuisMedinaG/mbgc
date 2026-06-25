import Foundation

@MainActor
@Observable
final class ImportViewModel {
    var bggUsername: String = ""
    var isLoading = false
    var isSyncing = false
    var errorMessage: String?
    var result: SyncResult?
    var hasBGGUsername = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let profile = try await APIClient.shared.getProfile()
            bggUsername = profile.bggUsername
            hasBGGUsername = !profile.bggUsername.isEmpty
        } catch {
            errorMessage = "Couldn't load profile."
        }
    }

    func sync() async {
        isSyncing = true
        errorMessage = nil
        result = nil
        defer { isSyncing = false }
        do {
            result = try await APIClient.shared.syncBGG()
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Sync failed."
        }
    }
}

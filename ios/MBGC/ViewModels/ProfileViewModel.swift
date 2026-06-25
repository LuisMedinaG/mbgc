import Foundation

@MainActor
@Observable
final class ProfileViewModel {
    var username: String = ""
    var bggUsername: String = ""
    var bggInput: String = ""
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var successMessage: String?

    func load() async {
        // ponytail: profile is server-side + authed; inert until the local
        // BGG-import port. No network on appear.
    }

    func saveBGG() async {
        let trimmed = bggInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            try await APIClient.shared.setBGGUsername(trimmed)
            bggUsername = trimmed
            successMessage = "Saved"
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't save."
        }
    }
}

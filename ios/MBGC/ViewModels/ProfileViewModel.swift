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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let profile = try await APIClient.shared.getProfile()
            username = profile.username
            bggUsername = profile.bggUsername
            bggInput = profile.bggUsername
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't load profile."
        }
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

import Foundation

private let kBGGUsername = "profile.bggUsername"

@MainActor
@Observable
final class ProfileViewModel {
    var bggUsername: String = ""
    var bggInput: String = ""
    var isSaving = false
    var errorMessage: String?
    var successMessage: String?

    func load() async {
        bggUsername = UserDefaults.standard.string(forKey: kBGGUsername) ?? ""
        bggInput = bggUsername
    }

    func saveBGG() {
        let trimmed = bggInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }
        UserDefaults.standard.set(trimmed, forKey: kBGGUsername)
        bggUsername = trimmed
        successMessage = "Saved"
    }
}

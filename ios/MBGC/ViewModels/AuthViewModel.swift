import Foundation

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticated: Bool
    var errorMessage: String?
    var isLoading = false

    init() {
        isAuthenticated = Keychain.get(Tokens.access) != nil
        // ponytail: nonisolated task avoids sending non-Sendable Notification across actor boundary (Xcode 16 SDK)
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .authSessionExpired) {
                await MainActor.run { self?.isAuthenticated = false }
            }
        }
    }

    func login(username: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await APIClient.shared.login(username: username, password: password)
            Keychain.set(result.accessToken, key: Tokens.access)
            isAuthenticated = true
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Login failed. Check your connection and try again."
        }
    }

    func logout() {
        Keychain.delete(Tokens.access)
        isAuthenticated = false
        // Revoke the refresh cookie server-side; non-blocking so the UI flips instantly.
        Task { await APIClient.shared.logout() }
    }
}

import Foundation

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticated: Bool
    var errorMessage: String?
    var isLoading = false

    init() {
        isAuthenticated = Keychain.get(Tokens.access) != nil
        // ponytail: addObserver avoids for-await over non-Sendable Notification (Swift 6.0/Xcode 16 compat).
        // Token not stored — AuthViewModel lives for app lifetime; [weak self] prevents retain cycle.
        NotificationCenter.default.addObserver(
            forName: .authSessionExpired, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isAuthenticated = false }
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

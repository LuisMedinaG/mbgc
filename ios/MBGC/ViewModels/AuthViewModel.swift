import Foundation

@Observable
final class AuthViewModel {
    var isAuthenticated: Bool
    var errorMessage: String?
    var isLoading = false

    init() {
        isAuthenticated = Keychain.get(Tokens.access) != nil
    }

    func login(username: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await APIClient.shared.login(username: username, password: password)
            Keychain.set(result.accessToken, key: Tokens.access)
            Keychain.set(result.refreshToken, key: Tokens.refresh)
            isAuthenticated = true
        } catch APIError.server(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = "Login failed. Check your connection and try again."
        }
    }

    func logout() {
        Keychain.delete(Tokens.access)
        Keychain.delete(Tokens.refresh)
        isAuthenticated = false
    }
}

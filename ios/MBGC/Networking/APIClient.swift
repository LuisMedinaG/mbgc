import Foundation

enum APIError: Error {
    case server(code: String, message: String)
    case unauthorized
    case transport(Error)
    case decoding(Error)
}

extension Notification.Name {
    /// Posted when a 401 retry's token refresh fails — the session is over.
    static let authSessionExpired = Notification.Name("authSessionExpired")
}

struct LoginResult: Decodable {
    let accessToken: String
    let expiresIn: Int
    // No refreshToken: the API returns it as an HttpOnly `mbgc_refresh` cookie,
    // not in the JSON body. URLSession's cookie storage carries it automatically.
}

struct Envelope<T: Decodable>: Decodable { let data: T }
struct ListEnvelope<T: Decodable>: Decodable {
    let data: [T]
    let meta: PageMeta
}
struct PageMeta: Decodable { let page: Int; let limit: Int; let total: Int }
private struct ErrorEnvelope: Decodable { let error: APIErrorBody }
private struct APIErrorBody: Decodable { let code: String; let message: String }

actor APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    // Dedupes concurrent 401s onto one in-flight refresh instead of firing one per request.
    private var refreshTask: Task<LoginResult, Error>?

    private init() {
        #if DEBUG
        // `localhost` only resolves to the Mac from the simulator (shared host
        // network) — on a physical device it means the phone itself. The Mac's
        // mDNS hostname (`<name>.local`) works from both and survives DHCP
        // reassigning the LAN IP. Override with MBGC_API_BASE_URL if needed.
        baseURL = ProcessInfo.processInfo.environment["MBGC_API_BASE_URL"] ?? "http://Luis-macbook-pro.local:8080"
        #else
        baseURL = "https://api.lumedina.dev"
        #endif
    }

    func login(username: String, password: String) async throws -> LoginResult {
        struct Body: Encodable { let username: String; let password: String }
        let body = try encoder.encode(Body(username: username, password: password))
        let envelope: Envelope<LoginResult> = try await send(
            path: "/api/v1/auth/login", method: "POST", jsonBody: body, authorized: false)
        return envelope.data
    }

    func listGames(query: String? = nil) async throws -> [GameDTO] {
        var path = "/api/v1/games"
        if let query, !query.isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path += "?q=\(encoded)"
        }
        let envelope: ListEnvelope<GameDTO> = try await send(
            path: path, method: "GET", jsonBody: nil, authorized: true)
        return envelope.data
    }

    private func refreshTokens() async throws -> LoginResult {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task<LoginResult, Error> {
            // The refresh token lives in the HttpOnly `mbgc_refresh` cookie, which
            // URLSession resends automatically — no request body required.
            let envelope: Envelope<LoginResult> = try await send(
                path: "/api/v1/auth/refresh", method: "POST", jsonBody: nil, authorized: false)
            return envelope.data
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Best-effort server logout: revokes the session and clears the refresh cookie.
    func logout() async {
        guard let url = URL(string: baseURL + "/api/v1/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = Keychain.get(Tokens.access) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        _ = try? await session.data(for: request)
    }

    private func send<T: Decodable>(
        path: String, method: String, jsonBody: Data?, authorized: Bool, retrying: Bool = false
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.transport(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonBody
        if authorized, let token = Keychain.get(Tokens.access) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, authorized, !retrying {
            do {
                let tokens = try await refreshTokens()
                Keychain.set(tokens.accessToken, key: Tokens.access)
            } catch {
                // Refresh cookie is gone or expired — session is over. Clear the
                // access token and notify AuthViewModel so the app drops to login.
                Keychain.delete(Tokens.access)
                NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                throw APIError.unauthorized
            }
            return try await send(
                path: path, method: method, jsonBody: jsonBody, authorized: authorized, retrying: true)
        }

        guard (200...299).contains(status) else {
            if let err = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(code: err.error.code, message: err.error.message)
            }
            throw status == 401 ? APIError.unauthorized : APIError.server(code: "unknown", message: "Request failed (\(status))")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

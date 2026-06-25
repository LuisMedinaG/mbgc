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
}

struct Envelope<T: Decodable>: Decodable { let data: T }
struct ListEnvelope<T: Decodable>: Decodable {
    let data: [T]
    let meta: PageMeta
}
struct PageMeta: Decodable { let page: Int; let limit: Int; let total: Int }
private struct ErrorEnvelope: Decodable { let error: APIErrorBody }
private struct APIErrorBody: Decodable { let code: String; let message: String }

struct ProfileDTO: Decodable { let username: String; let bggUsername: String }
// Mirrors services/api/internal/importer.SyncResult — also the response shape
// for CSVImport (ImportBGGIDs returns the same type).
struct SyncResult: Decodable { let imported: Int; let skipped: Int; let failed: [String] }
struct CSVPreviewRow: Decodable, Identifiable {
    let bggId: Int
    let name: String
    var id: Int { bggId }
}
struct Collection: Decodable, Identifiable { let id: Int; let name: String; let description: String; let gameCount: Int }

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

    func listGames(query: String? = nil, onPage: (@MainActor (Int, Int) -> Void)? = nil) async throws -> [GameDTO] {
        var games: [GameDTO] = []
        var page = 1
        let limit = 100
        while true {
            var components = URLComponents()
            var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(limit))]
            if let query, !query.isEmpty {
                items.append(URLQueryItem(name: "q", value: query))
            }
            components.queryItems = items
            let path = "/api/v1/games?" + (components.percentEncodedQuery ?? "")
            let envelope: ListEnvelope<GameDTO> = try await send(
                path: path, method: "GET", jsonBody: nil, authorized: true)
            games += envelope.data
            if let onPage { await onPage(games.count, envelope.meta.total) }
            // ponytail: walks all pages so library refresh never drops rows past page 1
            if envelope.data.isEmpty || games.count >= envelope.meta.total {
                break
            }
            page += 1
        }
        return games
    }

    func getGame(id: Int) async throws -> GameDetailDTO {
        let envelope: Envelope<GameDetailDTO> = try await send(
            path: "/api/v1/games/\(id)", method: "GET", jsonBody: nil, authorized: true)
        return envelope.data
    }

    func deleteGame(id: Int) async throws {
        struct Empty: Decodable {}
        let _: Envelope<Empty> = try await send(
            path: "/api/v1/games/\(id)", method: "DELETE", jsonBody: nil, authorized: true)
    }

    func setGameCollections(gameId: Int, collectionIds: [Int]) async throws {
        struct Body: Encodable { let collectionIds: [Int] }
        let body = try encoder.encode(Body(collectionIds: collectionIds))
        struct Empty: Decodable {}
        let _: Envelope<Empty> = try await send(
            path: "/api/v1/games/\(gameId)/collections", method: "POST", jsonBody: body, authorized: true)
    }

    func updateRulesUrl(gameId: Int, rulesUrl: String) async throws {
        struct Body: Encodable { let rulesUrl: String }
        let body = try encoder.encode(Body(rulesUrl: rulesUrl))
        struct Empty: Decodable {}
        let _: Envelope<Empty> = try await send(
            path: "/api/v1/games/\(gameId)/rules-url", method: "PUT", jsonBody: body, authorized: true)
    }

    func listCollections() async throws -> [Collection] {
        let envelope: Envelope<[Collection]> = try await send(
            path: "/api/v1/collections", method: "GET", jsonBody: nil, authorized: true)
        return envelope.data
    }

    func getProfile() async throws -> ProfileDTO {
        let envelope: Envelope<ProfileDTO> = try await send(
            path: "/api/v1/profile", method: "GET", jsonBody: nil, authorized: true)
        return envelope.data
    }

    func setBGGUsername(_ username: String) async throws {
        struct Body: Encodable { let bggUsername: String }
        let body = try encoder.encode(Body(bggUsername: username))
        struct Empty: Decodable {}
        let _: Envelope<Empty> = try await send(
            path: "/api/v1/profile/bgg-username", method: "PUT", jsonBody: body, authorized: true)
    }

    func syncBGG(fullRefresh: Bool = false) async throws -> SyncResult {
        let path = fullRefresh ? "/api/v1/import/sync?full_refresh=true" : "/api/v1/import/sync"
        let envelope: Envelope<SyncResult> = try await send(
            path: path, method: "POST", jsonBody: nil, authorized: true)
        return envelope.data
    }

    func csvPreview(fileData: Data, filename: String) async throws -> [CSVPreviewRow] {
        let boundary = "Boundary-\(UUID().uuidString)"
        var formData = Data()
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"csv_file\"; filename=\"\(filename)\"\r\n\r\n".data(using: .utf8)!)
        formData.append(fileData)
        formData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: baseURL + "/api/v1/import/csv/preview") else {
            throw APIError.transport(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = Keychain.get(Tokens.access) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = formData

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw APIError.server(code: "unknown", message: "Upload failed (\(status))")
        }
        let envelope = try decoder.decode(ListEnvelope<CSVPreviewRow>.self, from: data)
        return envelope.data
    }

    func csvImport(bggIds: [Int]) async throws -> SyncResult {
        struct Body: Encodable { let bggIds: [Int] }
        let body = try encoder.encode(Body(bggIds: bggIds))
        let envelope: Envelope<SyncResult> = try await send(
            path: "/api/v1/import/csv", method: "POST", jsonBody: body, authorized: true)
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

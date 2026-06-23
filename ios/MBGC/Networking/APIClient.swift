import Foundation

enum APIError: Error {
    case server(code: String, message: String)
    case unauthorized
    case transport(Error)
    case decoding(Error)
}

struct LoginResult: Decodable {
    let accessToken: String
    let refreshToken: String
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

final class APIClient {
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

    private init() {
        baseURL = ProcessInfo.processInfo.environment["MBGC_API_BASE_URL"] ?? "http://localhost:8080"
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
        guard let token = Keychain.get(Tokens.refresh) else { throw APIError.unauthorized }
        struct Body: Encodable { let refreshToken: String }
        let body = try encoder.encode(Body(refreshToken: token))
        let envelope: Envelope<LoginResult> = try await send(
            path: "/api/v1/auth/refresh", method: "POST", jsonBody: body, authorized: false)
        return envelope.data
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
            let tokens = try await refreshTokens()
            Keychain.set(tokens.accessToken, key: Tokens.access)
            Keychain.set(tokens.refreshToken, key: Tokens.refresh)
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

import Foundation

enum BGGError: Error, LocalizedError {
    case badURL
    case emptyResponse(ids: [Int])
    case xmlParse(Error)
    case http(status: Int)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: "Invalid BGG URL"
        case .emptyResponse(let ids): "BGG returned no data for \(ids.count) games"
        case .xmlParse(let err): "XML parse error: \(err.localizedDescription)"
        case .http(let status): "BGG returned status \(status)"
        case .transport(let err): "Network error: \(err.localizedDescription)"
        }
    }

    var userMessage: String {
        switch self {
        case .badURL:
            "Couldn't build the BGG request."
        case .emptyResponse:
            "BGG returned no game details. Try again later."
        case .xmlParse:
            "BGG returned an unreadable response. Try again later."
        case .http(status: 401):
            "BGG rejected the API token. Check the token and try again."
        case .http(status: 202):
            "BGG is still preparing the collection. Try again in a few minutes."
        case .http(status: 429):
            "BGG is rate limiting requests. Try again later."
        case .http:
            "BGG is unavailable right now. Try again later."
        case .transport:
            "Couldn't reach BGG. Check your connection and try again."
        }
    }
}

actor BGGClient {
    static let shared = BGGClient()

    private let session: URLSession
    private let batchSize = 20
    private let maxAttempts = 4
    private let requestDelay: UInt64 = 5_000_000_000

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    func fetchCollection(username: String, token: String? = nil) async throws -> CollectionResult {
        var components = URLComponents(string: "https://boardgamegeek.com/xmlapi2/collection")
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "own", value: "1"),
            URLQueryItem(name: "stats", value: "1")
        ]
        guard let url = components?.url else {
            throw BGGError.badURL
        }

        var delay = requestDelay
        for attempt in 1...maxAttempts {
            try await Task.sleep(nanoseconds: requestDelay)

            let request = request(for: url, token: token)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                if attempt == maxAttempts { throw BGGError.transport(error) }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? 0
            if status == 202 || status == 429 || status >= 500 {
                if attempt == maxAttempts { throw BGGError.http(status: status) }
                try await Task.sleep(nanoseconds: retryDelay(from: httpResponse, fallback: delay))
                delay *= 2
                continue
            }
            guard (200...299).contains(status) else {
                throw BGGError.http(status: status)
            }

            do {
                return try BGGXMLParser.parseCollectionResponse(data)
            } catch {
                throw BGGError.xmlParse(error)
            }
        }
        return CollectionResult(ids: [], userRatings: [:])
    }

    /// `onProgress(done, total)` is called on each completed batch.
    func fetchThings(
        ids: [Int],
        token: String? = nil,
        userRatings: [Int: Double] = [:],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [BGGGame] {
        var allGames: [BGGGame] = []
        let total = ids.count
        for i in stride(from: 0, to: total, by: batchSize) {
            let end = min(i + batchSize, total)
            let batch = Array(ids[i..<end])
            let games = try await fetchBatch(batch, token: token)
            allGames.append(contentsOf: games)
            onProgress?(allGames.count, total)
        }
        guard !userRatings.isEmpty else { return allGames }
        return allGames.map { game in
            var g = game
            g.userRating = userRatings[game.bggId] ?? 0
            return g
        }
    }

    private func fetchBatch(_ ids: [Int], token: String?) async throws -> [BGGGame] {
        let idStr = ids.map(String.init).joined(separator: ",")
        let urlStr = "https://boardgamegeek.com/xmlapi2/thing?id=\(idStr)&stats=1"
        guard let url = URL(string: urlStr) else {
            throw BGGError.badURL
        }

        var delay: UInt64 = 500_000_000
        for attempt in 1...maxAttempts {
            try await Task.sleep(nanoseconds: requestDelay)

            let request = request(for: url, token: token)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                if attempt == maxAttempts { throw BGGError.transport(error) }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? 0
            guard (200...299).contains(status) else {
                if attempt == maxAttempts { throw BGGError.http(status: status) }
                try await Task.sleep(nanoseconds: retryDelay(from: httpResponse, fallback: delay))
                delay *= 2
                continue
            }

            let games: [BGGGame]
            do {
                games = try BGGXMLParser.parseThingResponse(data)
            } catch {
                if attempt == maxAttempts { throw BGGError.xmlParse(error) }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }

            if games.isEmpty {
                if attempt == maxAttempts { throw BGGError.emptyResponse(ids: ids) }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }

            return games
        }
        throw BGGError.emptyResponse(ids: ids)
    }

    private func retryDelay(from response: HTTPURLResponse?, fallback: UInt64) -> UInt64 {
        guard let raw = response?.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(raw), seconds >= 0 else { return fallback }
        return UInt64(seconds * 1_000_000_000)
    }

    private func request(for url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("app.lumedina.mbgc/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

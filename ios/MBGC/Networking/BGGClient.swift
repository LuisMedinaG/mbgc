import Foundation
import os

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

/// Async BGG API client.
///
/// This actor provides a centralized and thread-safe interface for interacting with the BoardGameGeek XML API2.
///
/// Key Architectural Features:
/// - **Actor Isolation**: Uses Swift actors to serialize all network state and configuration, ensuring no data races.
/// - **Pacing & Rate Limiting**: Implements a strict 5-second delay between requests to BGG to avoid aggressive
///   rate-limiting from their servers.
/// - **Resilience**: Includes exponential backoff and retries (up to 4 attempts) for transient failures (202, 429, 5xx).
/// - **Batching**: Handles BGG's batch limit (20 items per request) automatically in `fetchThings`.
actor BGGClient {
    static let shared = BGGClient()

    private let session: URLSession
    private let batchSize = 20   // BGG thing endpoint caps at 20 IDs per request
    private let maxAttempts = 4
    private let requestDelay: UInt64 = 5_000_000_000 // 5s between requests; BGG throttles hard on burst requests
    private var lastRequestTime: Date?
    // .debug lines surface in Console/Xcode when debugging; release builds drop them. No #if needed.
    private let log = Logger(subsystem: "app.lumedina.mbgc", category: "BGGClient")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    /// Fetches the public collection for a given BGG username.
    ///
    /// This method is the entry point for importing a user's library.
    /// Note: BGG often returns a 202 status when a collection is being prepared;
    /// the client automatically retries in these cases.
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
            try await waitForRateLimit()

            let request = request(for: url, token: token)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await perform(request, label: "collection \(username)")
            } catch let error as CancellationError {
                throw error
            } catch {
                log.debug("collection \(username, privacy: .public): transport error: \(error.localizedDescription, privacy: .public)")
                if attempt == maxAttempts { throw BGGError.transport(error) }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? 0
            // 202 = BGG is still building the collection export; must poll. 429/5xx = retry with backoff.
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
        throw BGGError.http(status: 0)
    }

    /// Fetches detailed game data ("things") for a list of BGG IDs.
    ///
    /// This method handles batching IDs into groups of 20 and provides progress updates.
    ///
    /// - Parameters:
    ///   - onProgress: A callback invoked after each batch completes, providing (currentCount, totalCount).
    func fetchThings(
        ids: [Int],
        token: String? = nil,
        userRatings: [Int: Double] = [:],
        wantToPlay: [Int: Bool] = [:],
        numberOfPlays: [Int: Int] = [:],
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
        if userRatings.isEmpty && wantToPlay.isEmpty && numberOfPlays.isEmpty { return allGames }
        return allGames.map { game in
            var g = game
            g.userRating = userRatings[game.bggId] ?? 0
            g.wantToPlay = wantToPlay[game.bggId] ?? false
            g.numberOfPlays = numberOfPlays[game.bggId] ?? 0
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
            try await waitForRateLimit()

            let request = request(for: url, token: token)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await perform(request, label: "thing batch (\(ids.count) ids)")
            } catch let error as CancellationError {
                throw error
            } catch {
                log.debug("thing batch (\(ids.count) ids): transport error: \(error.localizedDescription, privacy: .public)")
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

    // Honors BGG's Retry-After header (seconds). Falls back to exponential backoff if the header is absent.
    private func retryDelay(from response: HTTPURLResponse?, fallback: UInt64) -> UInt64 {
        guard let raw = response?.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(raw), seconds >= 0 else { return fallback }
        return UInt64(seconds * 1_000_000_000)
    }

    // Wraps session.data with per-request DEBUG logging: status, latency, payload size — the data needed to benchmark an import.
    private func perform(_ request: URLRequest, label: String) async throws -> (Data, URLResponse) {
        let start = ContinuousClock().now
        let (data, response) = try await session.data(for: request)
        let d = ContinuousClock().now - start
        let ms = d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        log.debug("\(label, privacy: .public): HTTP \(status) in \(ms)ms, \(data.count) bytes")
        return (data, response)
    }

    private func request(for url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("app.lumedina.mbgc/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func waitForRateLimit() async throws {
        if let lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequestTime)
            let waitSeconds = Double(requestDelay) / 1_000_000_000.0 - elapsed
            if waitSeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
}

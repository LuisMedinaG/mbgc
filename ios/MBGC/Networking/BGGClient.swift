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
}

actor BGGClient {
    static let shared = BGGClient()

    private let session: URLSession
    private let batchSize = 20
    private let maxAttempts = 4
    private let rpsDelay: UInt64 = 500_000_000

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    /// `onProgress(done, total)` is called on each completed batch.
    func fetchThings(
        ids: [Int],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [BGGGame] {
        var allGames: [BGGGame] = []
        let total = ids.count
        for i in stride(from: 0, to: total, by: batchSize) {
            let end = min(i + batchSize, total)
            let batch = Array(ids[i..<end])
            let games = try await fetchBatch(batch)
            allGames.append(contentsOf: games)
            onProgress?(allGames.count, total)
            if end < total {
                try await Task.sleep(nanoseconds: rpsDelay)
            }
        }
        return allGames
    }

    private func fetchBatch(_ ids: [Int]) async throws -> [BGGGame] {
        let idStr = ids.map(String.init).joined(separator: ",")
        let urlStr = "https://boardgamegeek.com/xmlapi2/thing?id=\(idStr)&stats=1"
        guard let url = URL(string: urlStr) else {
            throw BGGError.badURL
        }

        var delay: UInt64 = 500_000_000
        for attempt in 1...maxAttempts {
            try await Task.sleep(nanoseconds: rpsDelay)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(from: url)
            } catch {
                if attempt == maxAttempts { throw BGGError.transport(error) }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                if attempt == maxAttempts { throw BGGError.http(status: status) }
                try await Task.sleep(nanoseconds: delay)
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
}

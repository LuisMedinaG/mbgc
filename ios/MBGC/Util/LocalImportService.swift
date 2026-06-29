import Foundation
import SwiftData

struct LocalImportSummary {
    let imported: Int
    let skipped: Int
    let failed: [Int]
}

struct LocalImportResult {
    let summary: LocalImportSummary
    let newGames: [Game]
}

@MainActor
enum LocalImportService {
    static func uniqueIds(_ ids: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }

    static func saveFetchedGames(
        _ bggGames: [BGGGame],
        requestedIds: [Int],
        skipped: Int,
        in modelContext: ModelContext
    ) throws -> LocalImportResult {
        let fetchedById = Dictionary(grouping: bggGames, by: \.bggId).compactMapValues(\.first)
        var failedIds: [Int] = []
        var newGames: [Game] = []

        for id in requestedIds {
            if let bggGame = fetchedById[id] {
                let game = Game(bggGame: bggGame)
                modelContext.insert(game)
                newGames.append(game)
            } else {
                failedIds.append(id)
            }
        }

        let library = try LocalLibrary.ensureDefaultCollection(in: modelContext)
        LocalLibrary.add(newGames, to: library)
        try modelContext.save()

        return LocalImportResult(
            summary: LocalImportSummary(imported: newGames.count, skipped: skipped, failed: failedIds),
            newGames: newGames
        )
    }
}

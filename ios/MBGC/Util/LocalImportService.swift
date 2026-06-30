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

struct LocalImportPlan {
    let allIds: [Int]
    let existingIds: Set<Int>
    let idsToFetch: [Int]
    let skipped: Int
    let overLimit: Int
}

@MainActor
enum LocalImportService {
    static func uniqueIds(_ ids: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }

    static func planImport(
        ids: [Int],
        limit: Int? = nil,
        in modelContext: ModelContext
    ) -> LocalImportPlan {
        let allIds = uniqueIds(ids)
        let existingIds = LocalLibrary.existingBggIds(in: modelContext, from: allIds)
        let newIds = allIds.filter { !existingIds.contains($0) }
        let idsToFetch = limit.map { Array(newIds.prefix($0)) } ?? newIds
        let overLimit = max(0, newIds.count - idsToFetch.count)

        return LocalImportPlan(
            allIds: allIds,
            existingIds: existingIds,
            idsToFetch: idsToFetch,
            skipped: existingIds.count + overLimit,
            overLimit: overLimit
        )
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

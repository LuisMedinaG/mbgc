import Foundation
import Testing
@testable import MBGC

@MainActor
@Suite struct FinderFlowTests {
    /// Minimal Game with just the fields the funnel reads.
    private func game(_ id: Int, playtime: Int, minPlayers: Int, maxPlayers: Int) -> Game {
        Game(bggGame: BGGGame(
            bggId: id, name: "g\(id)", description: "",
            yearPublished: 0, image: "", thumbnail: "",
            minPlayers: minPlayers, maxPlayers: maxPlayers, playTime: playtime,
            categories: [], mechanics: [], types: [],
            weight: 0, rating: 0, geekRating: 0, bggRank: 0,
            userRating: 0, wantToPlay: false, numberOfPlays: 0,
            languageDependence: 0, recommendedPlayers: [], minAge: 0
        ))
    }

    @Test func carouselSelection_finder_FLOW_4_finder_FLOW_6() {
        let vibe = Collection(name: "Party")   // non-default, non-smart
        let g1 = game(1, playtime: 20, minPlayers: 1, maxPlayers: 4)
        let g2 = game(2, playtime: 90, minPlayers: 2, maxPlayers: 5)
        g1.collections = [vibe]
        g2.collections = [vibe]

        let flow = FinderFlow()
        flow.ownedGames = [g1, g2]
        flow.allCollections = [vibe]

        #expect(flow.picks.count == flow.funnel.count)
        #expect(flow.currentAxis == .vibe)

        let party = flow.options(at: 0).first!
        flow.select(at: 0, option: party)

        #expect(flow.picks[0]?.id == party.id)
        #expect(flow.isPageAnswered(at: 0))
        #expect(flow.visiblePage == 0)
        #expect(flow.survivors.map(\.bggId) == [1, 2])

        flow.select(at: 0, option: party)

        #expect(flow.picks[0] == nil)
        #expect(!flow.isPageAnswered(at: 0))
        #expect(flow.survivors.count == 2)
    }

    /// Changing an upstream answer must invalidate any downstream pick whose option
    /// no longer exists in the re-narrowed survivors (validatePicks cascade).
    @Test func upstreamChangeInvalidatesDownstreamPick() {
        let g1 = game(1, playtime: 20, minPlayers: 1, maxPlayers: 2)  // supports 1-2, Quick
        let g2 = game(2, playtime: 90, minPlayers: 3, maxPlayers: 4)  // supports 3-4, Medium

        let flow = FinderFlow()
        flow.ownedGames = [g1, g2]
        flow.allCollections = []

        // funnel = [vibe, category, complexity, players(3), duration(4)]
        let players2 = flow.options(at: 3).first { $0.id == "players:2" }!
        flow.select(at: 3, option: players2)
        #expect(flow.survivors.map(\.bggId) == [1])

        let quick = flow.options(at: 4).first!   // only g1 survives → Quick bucket
        flow.select(at: 4, option: quick)
        #expect(flow.picks[4]?.id == quick.id)

        // Swap the upstream players pick to one that excludes g1. g2 is now the only
        // survivor (Medium), so the Quick duration pick is stale and must be dropped.
        let players4 = flow.options(at: 3).first { $0.id == "players:4" }!
        flow.select(at: 3, option: players4)

        #expect(flow.survivors.map(\.bggId) == [2])
        #expect(!flow.options(at: 4).contains { $0.id == quick.id })
        #expect(flow.picks[4] == nil)   // cascade invalidated the downstream pick
    }

    @Test func emptyAxisAutoSkips_finder_FLOW_3() {
        let g1 = game(1, playtime: 20, minPlayers: 1, maxPlayers: 4)

        let flow = FinderFlow()
        flow.ownedGames = [g1]
        flow.allCollections = [] // no vibe collections → vibe axis has zero options
        flow.skipEmptySteps()

        #expect(flow.currentAxis == .players)
        #expect(flow.availableQuestionIndices.allSatisfy { !flow.options(at: $0).isEmpty })
    }
}

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

    /// Swipe-back maps to flow.back(); it must unwind one page at a time across the
    /// whole funnel (vibe → players → duration) and no-op at the start.
    @Test func backUnwindsEveryPage() {
        let vibe = Collection(name: "Party")   // non-default, non-smart
        let g1 = game(1, playtime: 20, minPlayers: 1, maxPlayers: 4)
        let g2 = game(2, playtime: 90, minPlayers: 2, maxPlayers: 5)
        g1.collections = [vibe]
        g2.collections = [vibe]

        let flow = FinderFlow()
        flow.ownedGames = [g1, g2]
        flow.allCollections = [vibe]

        // Forward through all three pages.
        #expect(flow.stepIndex == 0)
        #expect(flow.currentAxis == .vibe)
        flow.select(flow.currentOptions.first!)
        #expect(flow.stepIndex == 1)
        #expect(flow.currentAxis == .players)
        flow.select(flow.currentOptions.first!)
        #expect(flow.stepIndex == 2)
        #expect(flow.currentAxis == .duration)
        flow.select(flow.currentOptions.first!)
        #expect(flow.stepIndex == 3)

        // Back unwinds each page.
        flow.back(); #expect(flow.stepIndex == 2)
        flow.back(); #expect(flow.stepIndex == 1)
        flow.back(); #expect(flow.stepIndex == 0)
        // At the start it's a no-op (the view exits the test instead).
        flow.back(); #expect(flow.stepIndex == 0)
    }
}

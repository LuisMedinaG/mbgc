import Foundation
import Testing
@testable import MBGC

@Suite struct GameFiltersTests {
    /// Build a Game with only the fields the filter reads. 0 → stored as nil (see Game.apply).
    private func game(_ id: Int = 1, rating: Double = 0, userRating: Double = 0, weight: Double = 0,
                      playtime: Int = 0, minPlayers: Int = 0, maxPlayers: Int = 0,
                      bggRank: Int = 0, recommendedPlayers: [Int] = [], year: Int = 0) -> Game {
        Game(bggGame: BGGGame(
            bggId: id, name: "g\(id)", description: "",
            yearPublished: year, image: "", thumbnail: "",
            minPlayers: minPlayers, maxPlayers: maxPlayers, playTime: playtime,
            categories: [], mechanics: [], types: [],
            weight: weight, rating: rating, geekRating: 0, bggRank: bggRank,
            userRating: userRating, wantToPlay: false, numberOfPlays: 0,
            languageDependence: 0, recommendedPlayers: recommendedPlayers, minAge: 0
        ))
    }

    private func filter(_ field: FilterField, _ mode: FilterMode, _ value: Double) -> GameFilters {
        var f = GameFilters()
        f.specs[field] = FilterSpec(mode: mode, value: value)
        return f
    }

    @Test func emptyFiltersKeepEverything() {
        let games = [game(1, rating: 5), game(2, rating: 9)]
        #expect(GameFilters().apply(games).count == 2)
    }

    @Test func minimumRatingKeepsAtOrAbove() {
        let pass = game(1, rating: 8), fail = game(2, rating: 6)
        let out = filter(.rating, .minimum, 7).apply([pass, fail])
        #expect(out.map(\.bggId) == [pass.bggId])
    }

    // The regression: a missing field must NOT silently drop the game.
    @Test func unknownValuePassesFilter() {
        let unrated = game(rating: 0) // → nil rating
        #expect(filter(.rating, .minimum, 7).apply([unrated]).count == 1)
        let noUserRating = game(userRating: 0)
        #expect(filter(.userRating, .minimum, 7).apply([noUserRating]).count == 1)
        let noWeight = game(weight: 0)
        #expect(filter(.weight, .maximum, 2).apply([noWeight]).count == 1)
        let noTime = game(playtime: 0)
        #expect(filter(.playtime, .maximum, 60).apply([noTime]).count == 1)
        let noRank = game(bggRank: 0)
        #expect(filter(.bggRank, .maximum, 500).apply([noRank]).count == 1)
        let noRec = game(recommendedPlayers: [])
        #expect(filter(.bestFor, .exactly, 4).apply([noRec]).count == 1)
    }

    @Test func bestForFiltersRecommendedCounts() {
        let quad = game(1, recommendedPlayers: [3, 4, 5])
        let duo  = game(2, recommendedPlayers: [2, 3])
        // exactly 4 → only quad (contains 4)
        #expect(filter(.bestFor, .exactly,  4).apply([quad, duo]).map(\.bggId) == [quad.bggId])
        // minimum 4 → only quad (has a count ≥ 4)
        #expect(filter(.bestFor, .minimum,  4).apply([quad, duo]).map(\.bggId) == [quad.bggId])
        // maximum 2 → only duo (quad's lowest is 3, which is > 2)
        #expect(filter(.bestFor, .maximum,  2).apply([quad, duo]).map(\.bggId) == [duo.bggId])
    }

    @Test func bggRankMaximumKeepsTopGames() {
        let top  = game(1, bggRank: 100)
        let deep = game(2, bggRank: 2000)
        let out  = filter(.bggRank, .maximum, 500).apply([top, deep])
        #expect(out.map(\.bggId) == [top.bggId])
    }

    @Test func playersMinimumNeedsEnoughSeats() {
        let fits = game(1, minPlayers: 2, maxPlayers: 6)   // can seat 5
        let small = game(2, minPlayers: 2, maxPlayers: 4)  // cannot seat 5
        let out = filter(.players, .minimum, 5).apply([fits, small])
        #expect(out.map(\.bggId) == [fits.bggId])
    }

    @Test func unknownPlayersPasses() {
        let unknown = game(minPlayers: 0, maxPlayers: 0)
        #expect(filter(.players, .exactly, 4).apply([unknown]).count == 1)
    }

    @Test func titleLanguageSetAndTimesPlayedFiltersNarrowResults() {
        let keeper = game(1, rating: 8)
        keeper.name = "Ark Nova"
        keeper.languageDependence = 2
        keeper.mechanics = ["Card Drafting"]
        keeper.numberOfPlays = 3

        let miss = game(2, rating: 8)
        miss.name = "Catan"
        miss.languageDependence = 4
        miss.mechanics = ["Trading"]
        miss.numberOfPlays = 1

        var filters = GameFilters()
        filters.titleContains = "ark"
        filters.languageLevels = [2]
        filters.setFilters[.mechanics] = ["Card Drafting"]
        filters.specs[.timesPlayed] = FilterSpec(mode: .minimum, value: 2)

        #expect(filters.apply([keeper, miss]).map(\.bggId) == [1])
    }
}

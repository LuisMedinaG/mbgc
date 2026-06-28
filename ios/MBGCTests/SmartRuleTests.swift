import Foundation
import SwiftData
import Testing
@testable import MBGC

@Suite @MainActor struct SmartRuleTests {

    // MARK: - GameFilters Codable round-trip

    @Test func gameFiltersRoundTrips() throws {
        var f = GameFilters()
        f.specs[.rating] = FilterSpec(mode: .minimum, value: 7)
        f.specs[.bggRank] = FilterSpec(mode: .maximum, value: 500)
        f.setFilters[.mechanics] = ["Worker Placement", "Deck Building"]
        f.titleStartsWith = "C"
        f.languageLevels = [1, 2]

        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(GameFilters.self, from: data)
        #expect(back == f)
    }

    // MARK: - smartGames set operations

    /// In-memory container so @Relationship arrays (Collection.games) work.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Collection.self, Game.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func game(_ id: Int, rating: Double = 0) -> Game {
        Game(bggGame: BGGGame(
            bggId: id, name: "g\(id)", description: "",
            yearPublished: 0, image: "", thumbnail: "",
            minPlayers: 0, maxPlayers: 0, playTime: 0,
            categories: [], mechanics: [], types: [],
            weight: 0, rating: rating, geekRating: 0, bggRank: 0,
            userRating: 0, wantToPlay: false, numberOfPlays: 0,
            languageDependence: 0, recommendedPlayers: [], minAge: 0
        ))
    }

    private func smart(_ rule: SmartRule) -> Collection {
        let c = Collection(name: "smart")
        c.isSmart = true
        c.setRule(rule)
        return c
    }

    /// Builds A = {1,2}, B = {2,3} in a context; returns (ctx, A, B, allGames[1,2,3]).
    private func fixture() throws -> (ModelContext, Collection, Collection, [Game]) {
        let ctx = try makeContext()
        let g1 = game(1), g2 = game(2), g3 = game(3)
        [g1, g2, g3].forEach(ctx.insert)
        let a = Collection(name: "A"), b = Collection(name: "B")
        ctx.insert(a); ctx.insert(b)
        a.games = [g1, g2]
        b.games = [g2, g3]
        return (ctx, a, b, [g1, g2, g3])
    }

    @Test func combineIsUnion() throws {
        let (ctx, a, b, all) = try fixture()
        let s = smart(SmartRule(combine: [a.id, b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1, 2, 3])
    }

    @Test func intersectKeepsCommon() throws {
        let (ctx, a, b, all) = try fixture()
        let s = smart(SmartRule(intersect: [a.id, b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [2])
    }

    @Test func subtractRemovesMembers() throws {
        let (ctx, a, b, all) = try fixture()
        let s = smart(SmartRule(combine: [a.id], subtract: [b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1]) // A {1,2} minus B {2,3} = {1}
    }

    @Test func excludeIsSymmetricDifference() throws {
        let (ctx, a, b, all) = try fixture()
        let s = smart(SmartRule(combine: [a.id], exclude: [b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1, 3]) // A {1,2} △ B {2,3} = {1,3}
    }

    @Test func baseStartsFromInitialList() throws {
        let (ctx, a, b, all) = try fixture()
        // base = A {1,2}, subtract B {2,3} → {1}
        let s = smart(SmartRule(base: a.id, subtract: [b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1])
    }

    @Test func baseUnionsCombineLists() throws {
        let (ctx, a, b, all) = try fixture()
        // base = A {1,2}, combine B {2,3} → {1,2,3}
        let s = smart(SmartRule(base: a.id, combine: [b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1, 2, 3])
    }

    @Test func filtersNarrowTheSet() throws {
        let ctx = try makeContext()
        let g1 = game(1, rating: 9), g2 = game(2, rating: 5)
        ctx.insert(g1); ctx.insert(g2)
        let a = Collection(name: "A"); ctx.insert(a); a.games = [g1, g2]
        var rule = SmartRule(combine: [a.id])
        rule.filters.specs[.rating] = FilterSpec(mode: .minimum, value: 7)
        let s = smart(rule); ctx.insert(s)
        let out = s.smartGames(collections: [a, s], allGames: [g1, g2]).map(\.bggId)
        #expect(out == [1])
    }

    @Test func nonSmartAndEmptyReturnNothing() throws {
        let (ctx, a, _, all) = try fixture()
        // Non-smart collection → smartGames returns []
        #expect(a.smartGames(collections: [a], allGames: all).isEmpty)
        // Smart with empty rule → combine empty means base = allGames, no filters → all
        let s = smart(SmartRule()); ctx.insert(s)
        #expect(s.smartGames(collections: [s], allGames: all).count == all.count)
    }
}

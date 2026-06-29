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
        f.titleContains = "Catan"
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
        let s = smart(SmartRule(base: [a.id], subtract: [b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1])
    }

    @Test func baseUnionsMultipleSelectedLists() throws {
        let (ctx, a, b, all) = try fixture()
        // "From selected" = A {1,2} + B {2,3} → union {1,2,3}
        let s = smart(SmartRule(base: [a.id, b.id])); ctx.insert(s)
        let out = Set(s.smartGames(collections: [a, b, s], allGames: all).map(\.bggId))
        #expect(out == [1, 2, 3])
    }

    @Test func legacySingleBaseDecodes() throws {
        let (_, a, _, _) = try fixture()
        // Old persisted rules stored `base` as a single UUID, not an array.
        let json = "{\"base\":\"\(a.id.uuidString)\",\"combine\":[],\"intersect\":[],\"subtract\":[],\"exclude\":[]}"
        let rule = try JSONDecoder().decode(SmartRule.self, from: Data(json.utf8))
        #expect(rule.base == [a.id])
    }

    @Test func baseUnionsCombineLists() throws {
        let (ctx, a, b, all) = try fixture()
        // base = A {1,2}, combine B {2,3} → {1,2,3}
        let s = smart(SmartRule(base: [a.id], combine: [b.id])); ctx.insert(s)
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

@Suite @MainActor struct LocalImportServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Collection.self, Game.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func bggGame(_ id: Int, name: String? = nil) -> BGGGame {
        BGGGame(
            bggId: id,
            name: name ?? "g\(id)",
            description: "",
            yearPublished: 0,
            image: "",
            thumbnail: "",
            minPlayers: 0,
            maxPlayers: 0,
            playTime: 0,
            categories: [],
            mechanics: [],
            types: [],
            weight: 0,
            rating: 0,
            geekRating: 0,
            bggRank: 0,
            userRating: 0,
            wantToPlay: false,
            numberOfPlays: 0,
            languageDependence: 0,
            recommendedPlayers: [],
            minAge: 0
        )
    }

    @Test func bggImportSync2DedupesRequestedIDsInOrder() {
        #expect(LocalImportService.uniqueIds([3, 1, 3, 2, 1]) == [3, 1, 2])
    }

    @Test func bggImportSync2And3SavesFetchedGamesIntoDefaultLibrary() throws {
        let ctx = try makeContext()

        let result = try LocalImportService.saveFetchedGames(
            [bggGame(2, name: "Catan"), bggGame(1, name: "Ark Nova")],
            requestedIds: [1, 2, 3],
            skipped: 4,
            in: ctx
        )

        let games = try ctx.fetch(FetchDescriptor<Game>()).sorted { $0.bggId < $1.bggId }
        let collections = try ctx.fetch(FetchDescriptor<Collection>())
        let defaultCollection = collections.first(where: \.isDefault)
        let library = try #require(defaultCollection)

        #expect(result.summary.imported == 2)
        #expect(result.summary.skipped == 4)
        #expect(result.summary.failed == [3])
        #expect(result.newGames.map(\.bggId) == [1, 2])
        #expect(games.map(\.name) == ["Ark Nova", "Catan"])
        #expect(library.name == "Library")
        #expect(library.games.map(\.bggId).sorted() == [1, 2])
    }
}

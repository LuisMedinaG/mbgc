import Foundation
import Testing
@testable import MBGC

@Suite struct BGGXMLParserTests {
    @Test func bggImportSync1ParsesBGGCollectionIDs() throws {
        let xml = """
            <items totalitems="2">
              <item objecttype="thing" objectid="174430" subtype="boardgame" collid="1" />
              <item objecttype="thing" objectid="13" subtype="boardgame" collid="2" />
            </items>
            """.data(using: .utf8)!

        let result = try BGGXMLParser.parseCollectionResponse(xml)

        #expect(result.ids == [174430, 13])
    }

    @Test func bggImportSync1ParsesBGGCollectionIDsOnlyOnce() throws {
        let xml = """
            <items totalitems="3">
              <item objectid="13" />
              <item objectid="13" />
              <item objectid="0" />
            </items>
            """.data(using: .utf8)!

        let result = try BGGXMLParser.parseCollectionResponse(xml)

        #expect(result.ids == [13])
    }

    @Test func bggImportSync1ParsesPersonalCollectionFields() throws {
        let xml = """
            <items totalitems="2">
              <item objectid="174430">
                <status own="1" wanttoplay="1" />
                <numplays>5</numplays>
                <stats>
                  <rating value="8.5" />
                </stats>
              </item>
              <item objectid="13">
                <status own="1" wanttoplay="0" />
                <numplays>0</numplays>
                <stats>
                  <rating value="N/A" />
                </stats>
              </item>
            </items>
            """.data(using: .utf8)!

        let result = try BGGXMLParser.parseCollectionResponse(xml)

        #expect(result.ids == [174430, 13])
        #expect(result.userRatings == [174430: 8.5])
        #expect(result.wantToPlay == [174430: true])
        #expect(result.numberOfPlays == [174430: 5])
    }

    @Test func bggImportSync1ParsesThingMetadataAndPolls() throws {
        let xml = """
            <items>
              <item type="boardgame" id="174430">
                <thumbnail>https://example.test/thumb.jpg</thumbnail>
                <image>https://example.test/image.jpg</image>
                <name type="primary" value="Gloomhaven &amp; Jaws" />
                <description>Line &amp; one&lt;br/&gt;&lt;b&gt;bold&lt;/b&gt;</description>
                <yearpublished value="2017" />
                <minplayers value="1" />
                <maxplayers value="4" />
                <playingtime value="120" />
                <minage value="14" />
                <link type="boardgamecategory" value="Adventure" />
                <link type="boardgamemechanic" value="Campaign / Battle Card Driven" />
                <link type="boardgamesubdomain" value="Strategy Games" />
                <link type="boardgamedesigner" value="Isaac Childres" />
                <link type="boardgameartist" value="Alexandr Elichev" />
                <link type="boardgamepublisher" value="Cephalofair Games" />
                <statistics>
                  <ratings>
                    <average value="8.6" />
                    <bayesaverage value="8.2" />
                    <rank type="subtype" name="boardgame" value="3" />
                    <averageweight value="3.9" />
                  </ratings>
                </statistics>
                <poll name="language_dependence">
                  <results>
                    <result level="1" value="No necessary in-game text" numvotes="2" />
                    <result level="3" value="Moderate in-game text" numvotes="8" />
                  </results>
                </poll>
                <poll name="suggested_numplayers">
                  <results numplayers="1">
                    <result value="Best" numvotes="1" />
                    <result value="Recommended" numvotes="4" />
                    <result value="Not Recommended" numvotes="10" />
                  </results>
                  <results numplayers="2">
                    <result value="Best" numvotes="10" />
                    <result value="Recommended" numvotes="5" />
                    <result value="Not Recommended" numvotes="1" />
                  </results>
                  <results numplayers="4+">
                    <result value="Best" numvotes="3" />
                    <result value="Recommended" numvotes="4" />
                    <result value="Not Recommended" numvotes="1" />
                  </results>
                </poll>
              </item>
            </items>
            """.data(using: .utf8)!

        let games = try BGGXMLParser.parseThingResponse(xml)

        let game = try #require(games.first)
        #expect(games.count == 1)
        #expect(game.bggId == 174430)
        #expect(game.name == "Gloomhaven & Jaws")
        #expect(game.description == "Line & onebold")
        #expect(game.yearPublished == 2017)
        #expect(game.minPlayers == 1)
        #expect(game.maxPlayers == 4)
        #expect(game.playTime == 120)
        #expect(game.minAge == 14)
        #expect(game.categories == ["Adventure"])
        #expect(game.mechanics == ["Campaign / Battle Card Driven"])
        #expect(game.types == ["Strategy Games"])
        #expect(game.designers == ["Isaac Childres"])
        #expect(game.artists == ["Alexandr Elichev"])
        #expect(game.publishers == ["Cephalofair Games"])
        #expect(game.rating == 8.6)
        #expect(game.geekRating == 8.2)
        #expect(game.bggRank == 3)
        #expect(game.weight == 3.9)
        #expect(game.languageDependence == 3)
        #expect(game.recommendedPlayers == [2, 4])
    }

    @Test func bggImportSync2SkipsThingItemsWithoutValidID() throws {
        let xml = """
            <items>
              <item type="boardgame">
                <name type="primary" value="Missing ID" />
              </item>
              <item type="boardgame" id="0">
                <name type="primary" value="Zero ID" />
              </item>
              <item type="boardgame" id="13">
                <name type="primary" value="Catan" />
              </item>
            </items>
            """.data(using: .utf8)!

        let games = try BGGXMLParser.parseThingResponse(xml)

        #expect(games.map(\.bggId) == [13])
        #expect(games.map(\.name) == ["Catan"])
    }
}

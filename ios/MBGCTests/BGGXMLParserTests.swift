import Foundation
import Testing
@testable import MBGC

@Suite struct BGGXMLParserTests {
    @Test func parsesBGGCollectionIDs() throws {
        let xml = """
            <items totalitems="2">
              <item objecttype="thing" objectid="174430" subtype="boardgame" collid="1" />
              <item objecttype="thing" objectid="13" subtype="boardgame" collid="2" />
            </items>
            """.data(using: .utf8)!

        let result = try BGGXMLParser.parseCollectionResponse(xml)

        #expect(result.ids == [174430, 13])
    }

    @Test func parsesBGGCollectionIDsOnlyOnce() throws {
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
}

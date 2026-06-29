import Testing
@testable import MBGC

@Suite struct BGGCSVParserTests {
    @Test func bggImportSync1ParsesObjectIDsAndNames() {
        let rows = BGGCSVParser.parse("""
        objectid,objectname
        174430,Gloomhaven
        13,Catan
        """)

        #expect(rows == [
            BGGCSVRow(bggId: 174430, name: "Gloomhaven"),
            BGGCSVRow(bggId: 13, name: "Catan"),
        ])
    }

    @Test func bggImportSync1HandlesQuotedCommasEscapedQuotesAndDedupesIDs() {
        let rows = BGGCSVParser.parse(#"""
        objectid,objectname
        1,"Game, With Comma"
        1,Duplicate
        2,"Escaped ""Quote"""
        """#)

        #expect(rows == [
            BGGCSVRow(bggId: 1, name: "Game, With Comma"),
            BGGCSVRow(bggId: 2, name: "Escaped \"Quote\""),
        ])
    }

    @Test func bggImportSync1FindsHeaderAfterExportPreamble() {
        let rows = BGGCSVParser.parse("""
        BoardGameGeek Collection Export

        objectname,objectid,other
        Ark Nova,342942,ignored
        ,0,ignored
        Missing ID,,ignored
        Nameless,99,ignored
        """)

        #expect(rows == [
            BGGCSVRow(bggId: 342942, name: "Ark Nova"),
            BGGCSVRow(bggId: 99, name: "Nameless"),
        ])
    }

    @Test func bggImportSync1FallsBackWhenObjectNameIsMissing() {
        let rows = BGGCSVParser.parse("""
        objectid
        11
        """)

        #expect(rows == [BGGCSVRow(bggId: 11, name: "BGG #11")])
    }

    @Test func bggImportSync1PreservesQuotedNewlinesInsideFields() {
        let rows = BGGCSVParser.parse(#"""
        objectid,objectname
        7,"Line
        Break"
        8,Next
        """#)

        #expect(rows == [
            BGGCSVRow(bggId: 7, name: "Line\nBreak"),
            BGGCSVRow(bggId: 8, name: "Next"),
        ])
    }

    @Test func bggImportSync1ReturnsEmptyRowsWithoutObjectIDHeader() {
        #expect(BGGCSVParser.parse("id,name\n1,Catan").isEmpty)
    }
}

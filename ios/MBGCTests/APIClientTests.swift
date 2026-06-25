import Foundation
import Testing

@testable import MBGC

@Test func decodesGameListEnvelope() throws {
    let json = """
        {
          "data": [
            {
              "id": 1,
              "bgg_id": 13,
              "name": "Catan",
              "year_published": 1995,
              "thumbnail": null,
              "min_players": 3,
              "max_players": 4,
              "playtime": 90,
              "rules_url": null,
              "vibes": [{"id": 1, "name": "Strategy"}]
            }
          ],
          "meta": {"page": 1, "limit": 20, "total": 1}
        }
        """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let envelope = try decoder.decode(ListEnvelope<GameDTO>.self, from: json)

    #expect(envelope.data.count == 1)
    #expect(envelope.data[0].name == "Catan")
    #expect(envelope.data[0].thumbnail == nil)
    #expect(envelope.data[0].vibes.first?.name == "Strategy")
    #expect(envelope.meta.total == 1)
}

// Mirrors services/api/internal/importer.CSVPreviewRow {bgg_id, name} — no
// already_owned field exists server-side.
@Test func decodesCSVPreviewEnvelope() throws {
    let json = """
        { "data": [{"bgg_id": 174430, "name": "Gloomhaven"}], "meta": {"page": 1, "limit": 1, "total": 1} }
        """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let envelope = try decoder.decode(ListEnvelope<CSVPreviewRow>.self, from: json)

    #expect(envelope.data.count == 1)
    #expect(envelope.data[0].bggId == 174430)
    #expect(envelope.data[0].name == "Gloomhaven")
}

// Mirrors services/api/internal/importer.SyncResult {imported, skipped, failed[]}
// — also the response shape for CSVImport.
@Test func decodesSyncResultEnvelope() throws {
    let json = """
        { "data": {"imported": 2, "skipped": 1, "failed": ["bad-id"]} }
        """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let envelope = try decoder.decode(Envelope<SyncResult>.self, from: json)

    #expect(envelope.data.imported == 2)
    #expect(envelope.data.skipped == 1)
    #expect(envelope.data.failed == ["bad-id"])
}

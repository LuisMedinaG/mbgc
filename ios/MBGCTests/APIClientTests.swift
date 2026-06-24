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

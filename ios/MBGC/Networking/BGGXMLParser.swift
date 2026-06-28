import Foundation

struct CollectionResult {
    let ids: [Int]
    let userRatings: [Int: Double]
    let wantToPlay: [Int: Bool]
    let numberOfPlays: [Int: Int]
}

/// A high-performance XML parser for BoardGameGeek XML API2 responses.
///
/// This parser uses `XMLParser` (SAX-style) for memory efficiency. It utilizes specialized
/// delegates to handle different API endpoints (collection vs thing) while maintaining
/// a robust state machine to navigate BGG's nested XML structure.
enum BGGXMLParser {
    static func parseCollectionResponse(_ data: Data) throws -> CollectionResult {
        let delegate = CollectionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            if let error = parser.parserError {
                throw error
            }
            throw URLError(.cannotParseResponse)
        }
        return CollectionResult(ids: delegate.ids, userRatings: delegate.userRatings,
                               wantToPlay: delegate.wantToPlay, numberOfPlays: delegate.numberOfPlays)
    }

    static func parseThingResponse(_ data: Data) throws -> [BGGGame] {
        let delegate = ThingDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            if let err = parser.parserError {
                throw err
            }
            throw URLError(.cannotParseResponse)
        }
        return delegate.games
    }

    private static let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
        ("&#039;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&rsquo;", "'"), ("&lsquo;", "'"),
        ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}"), ("&mdash;", "—"), ("&ndash;", "–"),
        ("&bull;", "•"), ("&hellip;", "…")
    ]

    private static let numericEntityRegex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: [])

    fileprivate static func unescapeHTML(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = s
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle numeric entities like &#1234; or &#xABCD;
        if result.contains("&#") {
            result = unescapeNumericEntities(result)
        }

        return result
    }

    private static func unescapeNumericEntities(_ s: String) -> String {
        guard let regex = numericEntityRegex else { return s }
        var result = s
        let nsString = result as NSString
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let entityRange = match.range(at: 1)
            let entityStr = nsString.substring(with: entityRange)
            let codePoint: UInt32?
            if entityStr.hasPrefix("x") {
                codePoint = UInt32(entityStr.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(entityStr, radix: 10)
            }

            if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
            }
        }
        return result
    }

    /// SAX delegate for parsing the `/collection` endpoint.
    ///
    /// It extracts:
    /// - Game IDs (`objectid`)
    /// - User personal ratings
    /// - "Want to play" status
    /// - Number of recorded plays
    ///
    /// It handles deduplication of items as BGG sometimes returns duplicate entries in this endpoint.
    private final class CollectionDelegate: NSObject, XMLParserDelegate {
        var ids: [Int] = []
        var userRatings: [Int: Double] = [:]
        var wantToPlay: [Int: Bool] = [:]
        var numberOfPlays: [Int: Int] = [:]
        private var seen = Set<Int>() // BGG can return duplicate <item> entries; deduplicate by objectid
        private var currentId: Int = 0
        private var inStats = false
        private var inNumplays = false
        private var numplaysBuffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "item":
                let id = Int(attributeDict["objectid"] ?? "") ?? 0
                guard id > 0, !seen.contains(id) else { currentId = 0; return }
                ids.append(id)
                seen.insert(id)
                currentId = id
            case "stats" where currentId > 0:
                inStats = true
            case "rating" where inStats:
                if let val = attributeDict["value"], let r = Double(val) {
                    userRatings[currentId] = r
                }
            case "status" where currentId > 0:
                if attributeDict["wanttoplay"] == "1" { wantToPlay[currentId] = true }
            case "numplays" where currentId > 0:
                inNumplays = true
                numplaysBuffer = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inNumplays { numplaysBuffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "stats" { inStats = false }
            if elementName == "numplays" {
                if let n = Int(numplaysBuffer.trimmingCharacters(in: .whitespaces)), n > 0 {
                    numberOfPlays[currentId] = n
                }
                inNumplays = false
            }
            if elementName == "item" { currentId = 0; inStats = false }
        }
    }

    /// SAX delegate for parsing the `/thing` endpoint.
    ///
    /// This is the primary parser for detailed game metadata.
    ///
    /// **State Management**:
    /// BGG XML is deeply nested and reuses element names (e.g., `<rating>` appears for both
    /// the community average and the user's personal rating). This delegate uses explicit
    /// state flags (`inItem`, `inStatistics`, `inRatings`) to track context and ensure
    /// values are mapped to the correct properties.
    private final class ThingDelegate: NSObject, XMLParserDelegate {
        var games: [BGGGame] = []

        private var currentItemId: Int = 0
        private var currentElement: String = ""
        private var textBuffer: String = ""

        private var thumbnail: String = ""
        private var image: String = ""
        private var name: String = ""
        private var desc: String = ""
        private var yearPublished: Int = 0
        private var minPlayers: Int = 0
        private var maxPlayers: Int = 0
        private var playTime: Int = 0
        private var categories: [String] = []
        private var mechanics: [String] = []
        private var types: [String] = []
        private var designers: [String] = []
        private var artists: [String] = []
        private var publishers: [String] = []
        private var rating: Double = 0
        private var geekRating: Double = 0
        private var bggRank: Int = 0
        private var weight: Double = 0
        private var languageDependence: Int = 0
        private var minAge: Int = 0
        private var recommendedPlayers: [Int] = []

        private var inItem = false
        private var inStatistics = false
        private var inRatings = false

        private var currentPollName: String = ""
        private var langResults: [(level: Int, votes: Int)] = []
        private var playerGroups: [(numPlayers: Int, best: Int, recommended: Int, notRec: Int)] = []
        private var currentPlayerCount: Int = 0
        private var currentBest: Int = 0
        private var currentRecommended: Int = 0
        private var currentNotRec: Int = 0

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                     namespaceURI: String?, qualifiedName qName: String?,
                     attributes attributeDict: [String: String] = [:]) {
            currentElement = elementName
            textBuffer = ""

            switch elementName {
            case "item":
                inItem = true
                currentItemId = Int(attributeDict["id"] ?? "0") ?? 0
                resetGame()

            case "name" where inItem:
                if attributeDict["type"] == "primary" {
                    name = BGGXMLParser.unescapeHTML(attributeDict["value"] ?? "")
                }

            case "yearpublished" where inItem:
                yearPublished = Int(attributeDict["value"] ?? "") ?? 0
            case "minplayers" where inItem:
                minPlayers = Int(attributeDict["value"] ?? "") ?? 0
            case "maxplayers" where inItem:
                maxPlayers = Int(attributeDict["value"] ?? "") ?? 0
            case "playingtime" where inItem:
                playTime = Int(attributeDict["value"] ?? "") ?? 0
            case "minage" where inItem:
                minAge = Int(attributeDict["value"] ?? "") ?? 0

            case "link" where inItem:
                let linkType = attributeDict["type"] ?? ""
                let value = BGGXMLParser.unescapeHTML(attributeDict["value"] ?? "")
                switch linkType {
                case "boardgamecategory":  categories.append(value)
                case "boardgamemechanic":  mechanics.append(value)
                case "boardgamesubdomain": types.append(value)
                case "boardgamedesigner":  designers.append(value)
                case "boardgameartist":    artists.append(value)
                case "boardgamepublisher": publishers.append(value)
                default: break
                }

            case "statistics" where inItem:
                inStatistics = true
            case "ratings" where inStatistics:
                inRatings = true
            case "average" where inRatings:
                rating = Double(attributeDict["value"] ?? "") ?? 0
            case "bayesaverage" where inRatings:
                geekRating = Double(attributeDict["value"] ?? "") ?? 0
            case "rank" where inRatings:
                if attributeDict["type"] == "subtype", attributeDict["name"] == "boardgame",
                   let v = attributeDict["value"], let r = Int(v) {
                    bggRank = r
                }
            case "averageweight" where inRatings:
                weight = Double(attributeDict["value"] ?? "") ?? 0

            case "poll" where inItem:
                currentPollName = attributeDict["name"] ?? ""
                if currentPollName == "language_dependence" {
                    langResults = []
                } else if currentPollName == "suggested_numplayers" {
                    playerGroups = []
                }

            case "results" where !currentPollName.isEmpty:
                if currentPollName == "suggested_numplayers" {
                    let raw = attributeDict["numplayers"] ?? ""
                    currentPlayerCount = Int(raw.replacingOccurrences(of: "+", with: "")) ?? 0
                    currentBest = 0
                    currentRecommended = 0
                    currentNotRec = 0
                }

            case "result" where !currentPollName.isEmpty:
                if currentPollName == "language_dependence" {
                    let level = Int(attributeDict["level"] ?? "") ?? 0
                    let votes = Int(attributeDict["numvotes"] ?? "") ?? 0
                    langResults.append((level: level, votes: votes))
                } else if currentPollName == "suggested_numplayers" {
                    let votes = Int(attributeDict["numvotes"] ?? "") ?? 0
                    switch attributeDict["value"] {
                    case "Best": currentBest = votes
                    case "Recommended": currentRecommended = votes
                    case "Not Recommended": currentNotRec = votes
                    default: break
                    }
                }

            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                     namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "thumbnail" where inItem:
                thumbnail = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "image" where inItem:
                image = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "description" where inItem:
                desc = BGGXMLParser.unescapeHTML(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines))

            case "statistics":
                inStatistics = false
            case "ratings":
                inRatings = false

            case "results" where currentPollName == "suggested_numplayers":
                playerGroups.append((
                    numPlayers: currentPlayerCount,
                    best: currentBest,
                    recommended: currentRecommended,
                    notRec: currentNotRec
                ))

            case "poll":
                if currentPollName == "language_dependence" {
                    languageDependence = computeLanguageDependence()
                } else if currentPollName == "suggested_numplayers" {
                    recommendedPlayers = computeRecommendedPlayers()
                }
                currentPollName = ""

            case "item":
                games.append(BGGGame(
                    bggId: currentItemId,
                    name: name.isEmpty ? "(unnamed BGG \(currentItemId))" : name,
                    description: desc,
                    yearPublished: yearPublished,
                    image: image,
                    thumbnail: thumbnail,
                    minPlayers: minPlayers,
                    maxPlayers: maxPlayers,
                    playTime: playTime,
                    categories: categories,
                    mechanics: mechanics,
                    types: types,
                    weight: weight,
                    rating: rating,
                    geekRating: geekRating,
                    bggRank: bggRank,
                    userRating: 0,
                    wantToPlay: false,
                    numberOfPlays: 0,
                    languageDependence: languageDependence,
                    recommendedPlayers: recommendedPlayers,
                    designers: designers,
                    artists: artists,
                    publishers: publishers,
                    minAge: minAge
                ))
                inItem = false

            default:
                break
            }
        }

        private func resetGame() {
            thumbnail = ""
            image = ""
            name = ""
            desc = ""
            yearPublished = 0
            minPlayers = 0
            maxPlayers = 0
            playTime = 0
            categories = []
            mechanics = []
            types = []
            designers = []
            artists = []
            publishers = []
            rating = 0
            geekRating = 0
            bggRank = 0
            weight = 0
            languageDependence = 0
            minAge = 0
            recommendedPlayers = []
            currentPollName = ""
            langResults = []
            playerGroups = []
            inStatistics = false
            inRatings = false
        }

        /// Computes the language-dependence level based on community poll results.
        ///
        /// - Returns: The level (1-5) with the most community votes (mode), or 0 if no votes were cast.
        private func computeLanguageDependence() -> Int {
            guard !langResults.isEmpty else { return 0 }
            var bestLevel = 0
            var bestVotes = -1
            for r in langResults {
                if r.votes > bestVotes {
                    bestVotes = r.votes
                    bestLevel = r.level
                }
            }
            return bestVotes > 0 ? bestLevel : 0
        }

        /// Computes which player counts are "recommended" by the community.
        ///
        /// A player count is considered recommended if the sum of "Best" and "Recommended"
        /// votes exceeds "Not Recommended" votes. This logic matches the badge logic
        /// seen on BoardGameGeek.com.
        private func computeRecommendedPlayers() -> [Int] {
            var result: [Int] = []
            var seen = Set<Int>()
            for g in playerGroups {
                if g.best + g.recommended > g.notRec, !seen.contains(g.numPlayers) {
                    result.append(g.numPlayers)
                    seen.insert(g.numPlayers)
                }
            }
            return result
        }

    }
}

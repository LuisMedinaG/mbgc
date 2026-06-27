import Foundation

struct CollectionResult {
    let ids: [Int]
    let userRatings: [Int: Double]
}

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
        return CollectionResult(ids: delegate.ids, userRatings: delegate.userRatings)
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

    // SAX delegate that streams the BGG collection XML — only extracts item IDs and user ratings.
    private final class CollectionDelegate: NSObject, XMLParserDelegate {
        var ids: [Int] = []
        var userRatings: [Int: Double] = [:]
        private var seen = Set<Int>() // BGG can return duplicate <item> entries; deduplicate by objectid
        private var currentId: Int = 0
        private var inStats = false

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
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "stats" { inStats = false }
            if elementName == "item" { currentId = 0; inStats = false }
        }
    }

    // SAX delegate for the BGG thing endpoint. Explicit nesting flags (inItem, inStatistics, inRatings)
    // prevent collisions — BGG XML reuses element names like <rating> at different depths.
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
        private var rating: Double = 0
        private var geekRating: Double = 0
        private var bggRank: Int = 0
        private var weight: Double = 0
        private var languageDependence: Int = 0
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
                    name = unescapeHTML(attributeDict["value"] ?? "")
                }

            case "yearpublished" where inItem:
                yearPublished = Int(attributeDict["value"] ?? "") ?? 0
            case "minplayers" where inItem:
                minPlayers = Int(attributeDict["value"] ?? "") ?? 0
            case "maxplayers" where inItem:
                maxPlayers = Int(attributeDict["value"] ?? "") ?? 0
            case "playingtime" where inItem:
                playTime = Int(attributeDict["value"] ?? "") ?? 0

            case "link" where inItem:
                let linkType = attributeDict["type"] ?? ""
                let value = unescapeHTML(attributeDict["value"] ?? "")
                switch linkType {
                case "boardgamecategory": categories.append(value)
                case "boardgamemechanic": mechanics.append(value)
                case "boardgamesubdomain": types.append(value)
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
                desc = unescapeHTML(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines))

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
                    languageDependence: languageDependence,
                    recommendedPlayers: recommendedPlayers
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
            rating = 0
            geekRating = 0
            bggRank = 0
            weight = 0
            languageDependence = 0
            recommendedPlayers = []
            currentPollName = ""
            langResults = []
            playerGroups = []
            inStatistics = false
            inRatings = false
        }

        // Returns the language-dependence level with the most community votes (mode).
        // Returns 0 if no votes were cast (poll absent or all zeros).
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

        // A player count is "recommended" when (Best + Recommended) votes outnumber Not Recommended votes.
        // This mirrors the threshold BGG uses to display the green/yellow badges on game pages.
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

        private func unescapeHTML(_ s: String) -> String {
            guard s.contains("&") else { return s }
            var result = s
            let entities: [(String, String)] = [
                ("&amp;", "&"),
                ("&lt;", "<"),
                ("&gt;", ">"),
                ("&quot;", "\""),
                ("&apos;", "'"),
                ("&#039;", "'"),
                ("&#39;", "'"),
                ("&nbsp;", " "),
                ("&rsquo;", "'"),
                ("&lsquo;", "'"),
                ("&rdquo;", "\u{201D}"),
                ("&ldquo;", "\u{201C}"),
                ("&mdash;", "—"),
                ("&ndash;", "–")
            ]
            for (entity, replacement) in entities {
                result = result.replacingOccurrences(of: entity, with: replacement)
            }
            return result
        }
    }
}

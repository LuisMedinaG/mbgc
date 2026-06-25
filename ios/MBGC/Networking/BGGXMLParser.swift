import Foundation

enum BGGXMLParser {
    static func parseCollectionResponse(_ data: Data) throws -> [Int] {
        let delegate = CollectionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            if let error = parser.parserError {
                throw error
            }
            throw URLError(.cannotParseResponse)
        }
        return delegate.ids
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

    private final class CollectionDelegate: NSObject, XMLParserDelegate {
        var ids: [Int] = []
        private var seen = Set<Int>()

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            guard elementName == "item",
                  let id = Int(attributeDict["objectid"] ?? ""),
                  id > 0,
                  !seen.contains(id) else { return }
            // ponytail: collection sync only needs BGG IDs; /thing already fetches metadata.
            ids.append(id)
            seen.insert(id)
        }
    }

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
            weight = 0
            languageDependence = 0
            recommendedPlayers = []
            currentPollName = ""
            langResults = []
            playerGroups = []
            inStatistics = false
            inRatings = false
        }

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
                ("&nbsp;", " ")
            ]
            for (entity, replacement) in entities {
                result = result.replacingOccurrences(of: entity, with: replacement)
            }
            return result
        }
    }
}

import Foundation

/// Single home for the picker's behavior knobs. Change the flow here, not in the views.
enum FinderConfig {
    /// Order of questions in the picker. Reorder or trim to change the funnel.
    static let funnel: [FinderAxis] = [.vibe, .category, .complexity, .players, .duration]

    /// Largest distinct player count shown; counts at or above this fold into "N+".
    static let playerCap = 5

    /// Player-count button tints, lightest (few players) → deepest (many).
    static let playerTints = [
        "#DBEAFE", "#BFDBFE", "#93C5FD", "#60A5FA",
        "#3B82F6", "#2563EB", "#1D4ED8", "#1E40AF",
    ]

    /// Duration bucket button tints.
    static let durationTints: [DurationBucket: String] = [
        .quick:  "#DCFCE7", .short:   "#FEF9C3", .medium: "#FED7AA",
        .long:   "#FECACA", .unknown: "#E2E8F0",
    ]

    /// Complexity bucket button tints.
    static let complexityTints: [ComplexityBucket: String] = [
        .light:     "#DCFCE7", .medium:   "#FEF9C3",
        .heavy:     "#FED7AA", .veryHeavy: "#FECACA",
    ]

    /// Category option tints, cycled in order.
    static let categoryTints = [
        "#E0E7FF", "#FCE7F3", "#ECFDF5", "#FEF3C7",
        "#FEF9C3", "#DBEAFE", "#F3E8FF", "#FFE4E6",
    ]

    /// Maximum number of top categories shown as options.
    static let maxCategoryOptions = 8

    // MARK: - Ranking

    /// Scoring weights for the "Tonight's Pick" ranking.
    /// All signals are normalized to 0–1 before multiplication, so weights are directly comparable.
    /// Higher weight = stronger pull on the final order. Change numbers here to retune.
    struct RankingWeights {
        /// Your own BGG rating (0–10). Strongest signal — you know your taste.
        var userRating: Double = 3.0
        /// BGG Geek Rating / bayesaverage (0–10). Resists outlier inflation better than the plain average.
        var geekRating: Double = 2.0
        /// Flat bonus when BGG community recommends this game at the chosen player count.
        var recommendedPlayers: Double = 1.0
        /// BGG board game rank (rank 1 = full credit; rank 10 000+ ≈ 0). Global prestige signal.
        var bggRank: Double = 0.5
        /// Flat bonus for games marked "want to play" on BGG. Tiebreaker nudge, not an override —
        /// kept below geekRating's reach so a great unflagged game still beats a mediocre flagged one.
        var wantToPlay: Double = 1.0
    }

    static let rankingWeights = RankingWeights()

    /// Games ranked below this are treated as effectively unranked for the bggRank signal.
    static let rankCap: Double = 10_000

    /// Static score for a game — signals that are always known, regardless of funnel answers.
    /// Per-question signals (e.g. recommendedPlayers) live in FinderAxis.scoreContribution.
    static func score(_ game: Game) -> Double {
        let w = rankingWeights
        var s = 0.0

        if let ur = game.userRating, ur > 0 {
            s += w.userRating * (ur / 10)
        }
        if let gr = game.geekRating, gr > 0 {
            s += w.geekRating * (gr / 10)
        }
        if let rank = game.bggRank, rank > 0 {
            s += w.bggRank * (1.0 - min(Double(rank), rankCap) / rankCap)
        }
        if game.wantToPlay {
            s += w.wantToPlay
        }

        return s
    }
}

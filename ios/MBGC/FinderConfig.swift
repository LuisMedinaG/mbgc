import Foundation

/// Single home for the picker's behavior knobs. Change the flow here, not in the views.
enum FinderConfig {
    /// Order of questions in the picker. Reorder or trim to change the funnel.
    static let funnel: [FinderAxis] = [.vibe, .players, .duration]

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
}

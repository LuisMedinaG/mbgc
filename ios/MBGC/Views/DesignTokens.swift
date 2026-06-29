import SwiftUI

// MARK: — Design Tokens
//
// One source of truth for spacing, radii, typography, and surfaces across the app.
// Anything visual that would otherwise live as a magic number belongs here.
//
// ponytail: append-only. Token names are referenced by call sites — renaming
// breaks every screen. Add new tokens instead of mutating existing ones.

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let screen: CGFloat = 24
    /// Reserved breathing room above the home indicator on screens where the
    /// floating nav is hidden (quiz, result). 60pt clears the indicator on
    /// every iPhone without padding past the screen edge.
    static let floatingNavReserved: CGFloat = 60
}

// MARK: - Radius

enum Radius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xlarge: CGFloat = 32
    static let pill: CGFloat = 999
}

// MARK: - Typography
//
// SF Pro defaults. Use the `Typography` font builders so future tweaks land in
// one place; `.font(.title2.bold())` is acceptable when the screen needs an
// ad-hoc value not covered here.

enum Typography {
    static let screenTitle: Font = .system(size: 38, weight: .bold)
    static let sectionTitle: Font = .system(size: 22, weight: .semibold)
    static let cardTitle: Font = .system(size: 20, weight: .semibold)
    static let body: Font = .system(size: 17, weight: .regular)
    static let bodyEmphasis: Font = .system(size: 17, weight: .medium)
    static let metadata: Font = .system(size: 15, weight: .regular)
    static let caption: Font = .system(size: 13, weight: .regular)
    static let step: Font = .system(size: 15, weight: .medium)
    static let tab: Font = .system(size: 12, weight: .medium)
}

// MARK: - Surfaces

enum Surface {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let elevated = Color(.systemBackground)
    static let separator = Color(.separator).opacity(0.35)
    static let metadataText = Color.secondary
}

// MARK: - Accent
//
// Single brand accent. Drives selection state, primary CTAs, and the active
// tab indicator. `accentTint` is the soft fill for selected cards/pills.

enum BrandAccent {
    static let color: Color = .indigo
    static let tint: Color = Color.indigo.opacity(0.10)
    static let border: Color = Color.indigo
}

// MARK: - Reusable components
//
// Small, focused building blocks. Each is a single-purpose view so call sites
// stay readable and visual changes stay local.

// MARK: MetadataRow
//
// `star.fill 8.7 · person.2.fill 1–6 · clock.fill 120 min`
// One row, one component, used everywhere a game is summarized.

struct GameMetadataRow: View {
    let rating: Double?
    let minPlayers: Int?
    let maxPlayers: Int?
    let playtime: Int?
    var accentRating: Bool = true

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let r = rating, r > 0 {
                Label(String(format: "%.1f", r), systemImage: "star.fill")
                    .font(Typography.metadata)
                    .foregroundStyle(accentRating ? BrandAccent.color : Surface.metadataText)
            }
            if let lo = minPlayers, let hi = maxPlayers {
                let label = lo == hi ? "\(lo)" : "\(lo)–\(hi)"
                Label("\(label) players", systemImage: "person.2.fill")
                    .font(Typography.metadata)
                    .foregroundStyle(Surface.metadataText)
                    .lineLimit(1)
            }
            if let pt = playtime, pt > 0 {
                Label("\(pt) min", systemImage: "clock.fill")
                    .font(Typography.metadata)
                    .foregroundStyle(Surface.metadataText)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

// MARK: Floating tab bar

enum HomeTab { case collection, tonight }

struct FloatingTabBar: View {
    @Binding var tab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton("Collection", icon: "square.stack.fill", for: .collection)
            tabButton("Tonight",    icon: "moon.stars.fill",  for: .tonight)
        }
        .padding(Spacing.xs)
        .frame(height: 56)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func tabButton(_ label: String, icon: String, for target: HomeTab) -> some View {
        let isActive = tab == target
        return Button { tab = target } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(Typography.tab)
            }
            .foregroundStyle(isActive ? BrandAccent.color : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                isActive ? Capsule().fill(BrandAccent.tint) : Capsule().fill(Color.clear)
            )
            .contentShape(Capsule())
        }
        .accessibilityLabel(label)
    }
}

// MARK: Floating chrome button (back, menu, settings)
//
// Circular neutral surface, 44pt tap target. Used at the top of result, quiz,
// and detail screens — the same component across the app keeps headers aligned.

struct ChromeButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .accessibilityLabel(Text(systemName.replacingOccurrences(of: ".", with: " ")))
    }
}

// MARK: SectionTitle
//
// `22pt semibold`, neutral. Used as section headers across result and quiz screens.

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Typography.sectionTitle)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: ScreenTitle
//
// `38pt bold`. Top-of-screen hero title. Spaced from the safe area by 8pt;
// horizontal margin handled by the caller via `.padding(.horizontal, Spacing.screen)`.

struct ScreenTitle: View {
    let text: String
    var subtitle: String? = nil

    init(_ text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    init(text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(text)
                .font(Typography.screenTitle)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Pill (tag)
// Compact label for vibe / mechanic chips in result and quiz screens.

struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Surface.metadataText)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 2)
            .background(
                Capsule().fill(Color(.tertiarySystemFill))
            )
    }
}

// MARK: SelectableCard
//
// The single selectable component used across quiz steps.
// Neutral by default; accent fill + accent border when selected.
// A subtle checkmark on the trailing edge signals selection.

struct SelectableCard: View {
    let label: String
    let count: Int?
    let symbol: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? BrandAccent.color : Surface.metadataText)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    if let count {
                        Text("\(count) \(count == 1 ? "game" : "games")")
                            .font(Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(BrandAccent.color)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.large)
                    .fill(isSelected ? BrandAccent.tint : Surface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large)
                    .strokeBorder(
                        isSelected ? BrandAccent.border : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.large))
    }
}

// MARK: GameCoverImage
//
// Square cover thumbnail with consistent radius and a neutral placeholder for
// missing art. Same component everywhere → uniform image treatment.
//
// `size = nil` → fills the parent (use with `.aspectRatio(...)` on the parent).
// `size = N`    → fixed N×N frame, e.g. for ranking rows.

struct GameCoverImage: View {
    let url: URL?
    var size: CGFloat? = 64
    var cornerRadius: CGFloat = Radius.medium

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.tertiarySystemFill))
            if let size {
                CachedAsyncImage(url: url, size: size, cornerRadius: cornerRadius, contentMode: .fill)
            } else {
                CachedAsyncImage(url: url, size: nil, cornerRadius: cornerRadius, contentMode: .fill)
            }
            if url == nil {
                Image(systemName: "photo")
                    // Larger glyph for unbounded (hero/alternative) covers, smaller for fixed-size thumbnails.
                    .font(.system(size: size == nil ? 36 : 24, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(CoverFrame(size: size))
    }
}

private struct CoverFrame: ViewModifier {
    let size: CGFloat?

    func body(content: Content) -> some View {
        if let size {
            content.frame(width: size, height: size)
        } else {
            // No fixed size — parent owns layout (typically via .aspectRatio).
            content
        }
    }
}

// MARK: FlowLayout
//
// Minimal wrapping layout: places children left-to-right, wrapping to a new
// row when they exceed the proposed width. Used by FlowPills and tag lists.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.width ?? .infinity, subviews: subviews, spacing: spacing, runSpacing: runSpacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing, runSpacing: runSpacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat, runSpacing: CGFloat) {
            var x: CGFloat = 0; var y: CGFloat = 0; var lineHeight: CGFloat = 0
            for subview in subviews {
                let sz = subview.sizeThatFits(.unspecified)
                if x + sz.width > width, x > 0 {
                    x = 0
                    y += lineHeight + runSpacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, sz.height)
                x += sz.width + spacing
            }
            size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

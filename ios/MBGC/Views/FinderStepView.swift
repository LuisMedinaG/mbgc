import SwiftUI

/// A single quiz step: header (back / step counter / Skip), question, options.
/// `onBack` is always supplied; `nil` callers get a placeholder so the layout
/// stays symmetric.
struct FinderStepView: View {
    let axis: FinderAxis
    let options: [FinderOption]
    let survivorCount: Int
    let step: Int
    let total: Int
    let onSelect: (FinderOption) -> Void
    let onBack: (() -> Void)?

    // Grid geometry — only used for the vibe step.
    private var cols: Int {
        switch options.count {
        case ...4:  return 2
        case 5...9: return 3
        default:    return 4
        }
    }
    private var isScrollable: Bool { options.count > 9 }
    private var rows: Int { (options.count + cols - 1) / cols }
    private let gridSpacing: CGFloat = 10
    private var gridCols: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: cols)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            questionBlock
            if options.isEmpty {
                emptyState
            } else if axis.usesGrid { optionGrid } else { optionList }
        }
        .padding(.bottom, Spacing.floatingNavReserved)
        .swipeBack { onBack?() }
    }

    private var header: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text("Step \(step + 1) of \(total)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Skip") {
                onSelect(FinderOption(id: "skip", label: "Skip", count: survivorCount))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(axis.question)
                .font(.largeTitle.bold())
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(survivorCount) \(survivorCount == 1 ? "game" : "games") available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var optionGrid: some View {
        if isScrollable {
            ScrollView {
                LazyVGrid(columns: gridCols, spacing: gridSpacing) {
                    ForEach(options) { opt in optionButton(opt, fillsCell: true).frame(height: 90) }
                }
                .padding(.horizontal, 16)
            }
            .contentMargins(.bottom, 16, for: .scrollContent)
        } else {
            GeometryReader { geo in
                let rowH = (geo.size.height - CGFloat(rows - 1) * gridSpacing) / CGFloat(rows)
                LazyVGrid(columns: gridCols, spacing: gridSpacing) {
                    ForEach(options) { opt in optionButton(opt, fillsCell: true).frame(height: max(rowH, 60)) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing to choose from here")
                .font(.headline)
            Text("You don't have any options for this yet. Tap Skip to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var optionList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(options) { opt in optionButton(opt, fillsCell: false) }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    // fillsCell: grid steps impose a fixed cell height → fill it. Row steps give no
    // height → vertical padding sets the breathing room so rows aren't cramped.
    private func optionButton(_ option: FinderOption, fillsCell: Bool) -> some View {
        let bg: Color = option.tint.flatMap { Color(hex: $0) } ?? Color(.secondarySystemBackground)
        let fgPrimary:   Color = option.solidBg ? .white : Color(.label)
        let fgSecondary: Color = option.solidBg ? .white.opacity(0.75) : .secondary

        let content = VStack(spacing: 6) {
            if let sym = option.symbol {
                Image(systemName: sym)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(fgPrimary)
            }
            Text(option.label)
                .font(.title2.bold())
                .foregroundStyle(fgPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(option.count) \(option.count == 1 ? "game" : "games")")
                .font(.subheadline)
                .foregroundStyle(fgSecondary)
        }

        return Button { onSelect(option) } label: {
            Group {
                if fillsCell {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                        .padding(.vertical, Spacing.lg)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(FinderButtonStyle())
    }
}

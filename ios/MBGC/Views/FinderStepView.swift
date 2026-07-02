import SwiftUI

/// A single quiz step inside the Finder carousel.
struct FinderStepView: View {
    let axis: FinderAxis
    let options: [FinderOption]
    let survivorCount: Int
    let step: Int
    let total: Int
    let selectedOption: FinderOption?
    let onSelect: (FinderOption) -> Void

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
            if axis.usesGrid { optionGrid } else { optionList }
        }
        // finder.FLOW.9
        .padding(.bottom, Spacing.floatingNavReserved)
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            Text("Step \(step + 1) of \(total)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
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
        let isSelected = selectedOption?.id == option.id
        let isDimmed = selectedOption != nil && !isSelected

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
                    ZStack {
                        selectionBackground(bg: bg, isSelected: isSelected)
                        content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ZStack {
                        selectionBackground(bg: bg, isSelected: isSelected)
                        content
                            .padding(.vertical, Spacing.lg)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.primary.opacity(0.72) : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .background(.background, in: Circle())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .scaleEffect(isSelected ? 1.025 : 1)
            .opacity(isDimmed ? 0.48 : 1)
            .saturation(isDimmed ? 0.55 : 1)
            .shadow(color: .black.opacity(isSelected ? 0.16 : 0), radius: 14, y: 8)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: selectedOption?.id)
        }
        .buttonStyle(FinderButtonStyle())
    }

    // finder.FLOW.8
    private func selectionBackground(bg: Color, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(bg)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55)
                }
            }
    }
}

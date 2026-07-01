import SwiftUI

/// Shared UI for picking a collection's name, color, and icon — used by Create
/// and Rename sheets so the two flows stay visually identical.
/// `accessory` renders between the name field and the color grid
/// (e.g. the smart-list "Set Filters" pill).
struct CollectionPickerBody<Accessory: View>: View {
    @Binding var name: String
    @Binding var selectedColor: String
    @Binding var selectedIcon: String
    @ViewBuilder var accessory: () -> Accessory
    @FocusState private var focused: Bool

    init(
        name: Binding<String>,
        selectedColor: Binding<String>,
        selectedIcon: Binding<String>,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        _name = name
        _selectedColor = selectedColor
        _selectedIcon = selectedIcon
        self.accessory = accessory
    }

    static var colors: [String] { [
        "#3D4A52", "#8B4513", "#E040FB", "#9C27B0", "#5C35CC",
        "#2196F3", "#42A5F5", "#26C6DA", "#26A69A", "#4CAF50",
        "#66BB6A", "#FFA726", "#FF7043", "#F44336", "#EC407A",
    ] }
    static var icons: [String] { [
        "list.bullet",        "person.fill",        "crown.fill",           "bolt.fill",    "star.fill",
        "face.smiling",       "face.dashed",        "flag.fill",            "sun.max.fill", "moon.fill",
        "leaf.fill",          "hand.thumbsup.fill", "hand.thumbsdown.fill", "heart.fill",   "flame.fill",
        "theatermasks.fill",  "burst.fill",         "bookmark.fill",        "checkmark",    "xmark",
        "gift.fill",          "hand.raised.fill",   "trophy.fill",          "dice.fill",    "gamecontroller.fill",
    ] }

    // 6 columns with wider gaps keeps the icon grid airy.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 6)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(hex: selectedColor) ?? .blue)
                            .frame(width: 80, height: 80)
                        Image(systemName: selectedIcon)
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 24)

                    TextField("Name", text: $name)
                        .font(.system(size: 34, weight: .regular))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(name.isEmpty ? Color(.placeholderText) : Color(.label))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .focused($focused)
                        .onAppear { focused = true }
                }

                accessory()

                Divider()

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Self.colors, id: \.self) { colorSwatch(hex: $0) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

                Divider()

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Self.icons, id: \.self) { iconButton(icon: $0) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
    }

    @ViewBuilder
    private func colorSwatch(hex: String) -> some View {
        let isSelected = hex == selectedColor
        let color = Color(hex: hex) ?? .gray
        Button { selectedColor = hex } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2.5)
                        .opacity(isSelected ? 1 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color, lineWidth: isSelected ? 2.5 : 0)
                        .padding(-2.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconButton(icon: String) -> some View {
        let isSelected = icon == selectedIcon
        let accent = Color(hex: selectedColor) ?? .blue
        Button { selectedIcon = icon } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.15) : Color(.systemGray6))
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? accent : Color(.label))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent, lineWidth: isSelected ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The three kinds of list a user can create.
enum CollectionKind: String, CaseIterable, Identifiable {
    case standard, ranked, smart
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard List"
        case .ranked:   return "Ranked List"
        case .smart:    return "Smart List"
        }
    }
    var subtitle: String {
        switch self {
        case .standard: return "Organize your games."
        case .ranked:   return "Put your games in order."
        case .smart:    return "Filter your collection."
        }
    }
    var icon: String {
        switch self {
        case .standard: return "square.grid.2x2.fill"
        case .ranked:   return "star.fill"
        case .smart:    return "bolt.fill"
        }
    }
    var tint: Color {
        switch self {
        case .standard: return .orange
        case .ranked:   return .blue
        case .smart:    return .purple
        }
    }
    /// Default SF Symbol pre-selected in the create picker for this kind.
    var defaultIcon: String {
        switch self {
        case .standard: return "list.bullet"
        case .ranked:   return "star.fill"
        case .smart:    return "bolt.fill"
        }
    }
}

/// Inline floating card presented by the "+" button — pick a list type.
struct CreateTypeChooser: View {
    let onSelect: (CollectionKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CollectionKind.allCases) { kind in
                Button { onSelect(kind) } label: { row(kind) }
                    .buttonStyle(.plain)
            }
        }
        .background(Color(red: 0.99, green: 0.98, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func row(_ kind: CollectionKind) -> some View {
        HStack(spacing: 14) {
            Image(systemName: kind.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(kind.tint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.headline).foregroundStyle(.primary)
                Text(kind.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

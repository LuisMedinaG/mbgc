import SwiftData
import SwiftUI

// MARK: — Collections list

struct VibesView: View {
    /// Legacy name for the view model handling collection CRUD.
    let viewModel: VibesViewModel
    @Binding var path: [Collection]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query private var allGames: [Game]
    @State private var editingCollection: Collection?
    @State private var collectionToDelete: Collection?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Collection", subtitle: "\(collections.count) \(collections.count == 1 ? "list" : "lists")")
                    .padding(.horizontal, Spacing.screen)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.lg)

                if collections.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "square.stack",
                        description: Text("Tap + to create your first collection.")
                    )
                    Spacer()
                } else {
                    List(collections) { col in
                        NavigationLink(value: col) {
                            collectionRow(col)
                        }
                        .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.md, trailing: Spacing.lg))
                        .listRowBackground(Surface.card)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !col.isDefault {
                                Button(role: .destructive) {
                                    collectionToDelete = col
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingCollection = col
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationDestination(for: Collection.self) { col in
                CollectionDetailView(collection: col)
                    .toolbar(.visible, for: .navigationBar)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingCollection) { col in
                RenameCollectionSheet(collection: col, initialName: col.name)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Delete \"\(collectionToDelete?.name ?? "")\"?", isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let col = collectionToDelete { viewModel.delete(col, modelContext: modelContext) }
                    collectionToDelete = nil
                }
                Button("Cancel", role: .cancel) { collectionToDelete = nil }
            }
        }
    }

    private func collectionRow(_ col: Collection) -> some View {
        HStack(spacing: Spacing.lg) {
            collectionIcon(col)
            Text(col.name)
                .font(Typography.bodyEmphasis)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count(for: col))")
                .font(Typography.bodyEmphasis)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    private func count(for col: Collection) -> Int {
        col.isSmart
            ? col.smartGames(collections: collections, allGames: allGames).count
            : col.games.count
    }

    private func collectionIcon(_ col: Collection) -> some View {
        let bg: Color = col.isDefault
            ? BrandAccent.color
            : Color(hex: col.effectiveColorHex) ?? .orange
        let icon = col.isDefault ? "square.grid.2x2.fill" : col.effectiveIconName
        return Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
    }
}

// MARK: — Shared color/icon picker (used by Create + Rename)

/// A shared UI component for picking a collection's name, color, and icon.
/// `accessory` renders between the name field and the color grid (e.g. the smart "Set Filters" pill).
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

    // ponytail: 6 cols + 18pt gaps = smaller, airier cells than 5 cols/10pt
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

// MARK: — Collection type chooser (Standard / Ranked / Smart)

/// The three kinds of list a user can create. Mirrors Overboard's create sheet.
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
/// One neutral card with three rows. The accent color (not saturated tints)
/// signals the active state, keeping the chooser calm.
struct CreateTypeChooser: View {
    let onSelect: (CollectionKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CollectionKind.allCases) { kind in
                Button { onSelect(kind) } label: { row(kind) }
                    .buttonStyle(.plain)
                if kind != CollectionKind.allCases.last {
                    Rectangle()
                        .fill(Surface.separator)
                        .frame(height: 1)
                        .padding(.leading, Spacing.xxl + 44)
                }
            }
        }
        .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    private func row(_ kind: CollectionKind) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: kind.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BrandAccent.color)
                .frame(width: 44, height: 44)
                .background(BrandAccent.tint, in: RoundedRectangle(cornerRadius: Radius.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(Typography.bodyEmphasis).foregroundStyle(.primary)
                Text(kind.subtitle).font(Typography.metadata).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }
}

// MARK: — Create sheet (own @Environment so modelContext is guaranteed)

struct CreateCollectionSheet: View {
    let kind: CollectionKind
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query private var allGames: [Game]
    @State private var name = ""
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var rule = SmartRule()
    @State private var showRuleEditor = false
    @State private var errorMessage: String?

    init(kind: CollectionKind) {
        self.kind = kind
        _selectedColor = State(initialValue: "#2196F3")
        _selectedIcon = State(initialValue: kind.defaultIcon)
    }

    var body: some View {
        NavigationStack {
            CollectionPickerBody(name: $name, selectedColor: $selectedColor, selectedIcon: $selectedIcon) {
                if kind == .smart { setFiltersPill }
            }
                .navigationTitle(CollectionName.trimmed(name).isEmpty ? "New Collection" : CollectionName.trimmed(name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { save() }
                            .disabled(CollectionName.trimmed(name).isEmpty)
                    }
                }
                .collectionSaveAlert($errorMessage)
                .sheet(isPresented: $showRuleEditor) {
                    SmartListEditor(rule: rule, lists: collections, allGames: allGames) { rule = $0 }
                }
        }
        .presentationDetents([.large])
    }

    private var setFiltersPill: some View {
        Button { showRuleEditor = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                Text("Set Filters").fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                Text("\(rule.activeCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Color.white, in: Circle())
            }
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .background(Color.green, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func save() {
        let col = Collection(name: CollectionName.prepareForSave(name), desc: "")
        col.colorHex = selectedColor
        col.iconName = selectedIcon
        switch kind {
        case .standard: break
        case .ranked:   col.isRanked = true
        case .smart:    col.isSmart = true; col.setRule(rule)
        }
        modelContext.insert(col)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Couldn't save collection."
        }
    }
}

// MARK: — Rename / edit sheet

struct RenameCollectionSheet: View {
    let collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var errorMessage: String?

    init(collection: Collection, initialName: String) {
        self.collection = collection
        _name = State(initialValue: initialName)
        _selectedColor = State(initialValue: collection.effectiveColorHex)
        _selectedIcon = State(initialValue: collection.effectiveIconName)
    }

    var body: some View {
        NavigationStack {
            CollectionPickerBody(name: $name, selectedColor: $selectedColor, selectedIcon: $selectedIcon)
                .navigationTitle(CollectionName.trimmed(name).isEmpty ? "Edit Collection" : CollectionName.trimmed(name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(CollectionName.trimmed(name).isEmpty)
                    }
                }
                .collectionSaveAlert($errorMessage)
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard !collection.isDefault else { return }
        collection.name = CollectionName.prepareForSave(name)
        collection.colorHex = selectedColor
        collection.iconName = selectedIcon
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Couldn't save collection."
        }
    }
}

private extension View {
    func collectionSaveAlert(_ message: Binding<String?>) -> some View {
        alert("Error", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    // Selection-bar pill: tinted text on the parent capsule, no per-button bg.
    func pillLabel(_ tint: Color) -> some View {
        self.fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
    }
}

// MARK: — Smart list rule editor

/// A specialized editor for defining `SmartRule` logic.
/// It allows users to combine, intersect, subtract, or exclude games from other
/// collections and apply attribute-based filters.
struct SmartListEditor: View {
    @State private var rule: SmartRule
    let lists: [Collection]
    let allGames: [Game]
    let onSave: (SmartRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activeBucket: Bucket?
    @State private var showBaseSelect = false
    @State private var baseSelected: Bool
    @State private var showTitlePicker = false
    @State private var activeChecklist: SetFilterField?

    private var baseCollections: [Collection] { lists.filter { rule.base.contains($0.id) } }

    private var baseSummary: String {
        if rule.base.isEmpty { return "Library" }
        if rule.base.count == 1 { return baseCollections.first?.name ?? "Library" }
        return "\(rule.base.count) lists"
    }

    init(rule: SmartRule, lists: [Collection], allGames: [Game], onSave: @escaping (SmartRule) -> Void) {
        _rule = State(initialValue: rule)
        self.lists = lists
        self.allGames = allGames
        self.onSave = onSave
        _baseSelected = State(initialValue: !rule.base.isEmpty || !rule.combine.isEmpty || !rule.intersect.isEmpty || !rule.subtract.isEmpty || !rule.exclude.isEmpty)
    }

    enum Bucket: String, CaseIterable, Identifiable {
        case combine = "Combine", intersect = "Intersect", subtract = "Subtract", exclude = "Exclude"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .combine:   return "plus.square.on.square"
            case .intersect: return "square.on.square.intersection.dashed"
            case .subtract:  return "minus.square"
            case .exclude:   return "xmark.square"
            }
        }
    }

    private func ids(_ b: Bucket) -> [UUID] {
        switch b {
        case .combine:   return rule.combine
        case .intersect: return rule.intersect
        case .subtract:  return rule.subtract
        case .exclude:   return rule.exclude
        }
    }
    private func setIds(_ v: [UUID], _ b: Bucket) {
        switch b {
        case .combine:   rule.combine = v
        case .intersect: rule.intersect = v
        case .subtract:  rule.subtract = v
        case .exclude:   rule.exclude = v
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Lists") {
                    baseRow
                    if baseSelected {
                        fromSelectedGroup
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        ForEach(Bucket.allCases) { bucket in
                            operationRow(bucket)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                FilterRows(filters: $rule.filters, games: allGames, showTitlePicker: $showTitlePicker, activeChecklist: $activeChecklist)
            }
            .navigationTitle("Smart Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(rule); dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $activeBucket) { bucket in
                ListPickerSheet(
                    title: bucket.rawValue,
                    lists: lists.filter { !rule.base.contains($0.id) },
                    selected: Binding(
                        get: { Set(ids(bucket)) },
                        set: { setIds(Array($0), bucket) }
                    )
                )
            }
            .sheet(isPresented: $showBaseSelect) {
                ListPickerSheet(
                    title: "Select Lists",
                    lists: lists,
                    selected: Binding(
                        get: { Set(rule.base) },
                        set: { rule.base = Array($0) }
                    )
                )
            }
            .sheet(item: $activeChecklist) { field in
                ChecklistPickerSheet(
                    title: field.rawValue,
                    options: field.values(from: allGames),
                    selected: Binding(
                        get: { rule.filters.setFilters[field] ?? [] },
                        set: { rule.filters.setFilters[field] = $0.isEmpty ? nil : $0 }
                    )
                )
            }
            .sheet(isPresented: $showTitlePicker) {
                TitleFilterSheet(text: $rule.filters.titleContains)
            }
        }
    }

    private var baseRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle").frame(width: 24).foregroundStyle(Color.red)
            Text("Lists").font(.body).foregroundStyle(.primary)
            Spacer()
            baseMenu
        }
    }

    private var baseMenu: some View {
        Menu {
            Button {
                baseSelected = false
                rule.base = []
                rule.combine = []; rule.intersect = []; rule.subtract = []; rule.exclude = []
            } label: {
                if baseSelected { Text("Off") } else { Label("Off", systemImage: "checkmark") }
            }
            Button {
                baseSelected = true                       // reveal ops panel inline; no sheet
            } label: {
                if baseSelected { Label("Choose…", systemImage: "checkmark") } else { Text("Choose…") }
            }
        } label: {
            HStack(spacing: 3) {
                Text(baseSelected ? "Choose…" : "Off")
                    .foregroundStyle(baseSelected ? Color.accentColor : .secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
    }

    private var fromSelectedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist").frame(width: 24).foregroundStyle(Color.accentColor)
            Text("From selected").font(.body).foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 3) {
                Text(baseSummary).foregroundStyle(rule.base.isEmpty ? .secondary : Color.accentColor)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
        }
        .contentShape(Rectangle())
        .onTapGesture { showBaseSelect = true }
    }

    private func selectedBaseRow(_ list: Collection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: list.isDefault ? "square.grid.2x2.fill" : list.effectiveIconName)
                .foregroundStyle(Color(hex: list.effectiveColorHex) ?? .orange).frame(width: 24)
            Text(list.name)
            Spacer()
            Text("\(list.games.count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // "From selected" + the chosen base lists, grouped in one tinted box.
    private var fromSelectedGroup: some View {
        VStack(spacing: 0) {
            fromSelectedRow
                .padding(.horizontal, 14).padding(.vertical, 12)
            ForEach(baseCollections) { list in
                Divider().padding(.leading, 14)
                selectedBaseRow(list)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .background(Color(red: 1.0, green: 0.95, blue: 0.82).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // One set operation, indented under the base with a ↳ and its own tinted capsule.
    private func operationRow(_ bucket: Bucket) -> some View {
        let count = ids(bucket).count
        return HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.subheadline).foregroundStyle(.secondary).frame(width: 18)
            Button { activeBucket = bucket } label: {
                HStack(spacing: 12) {
                    Image(systemName: bucket.icon).frame(width: 24).foregroundStyle(.primary)
                    Text(bucket.rawValue).font(.body).foregroundStyle(.primary)
                    Spacer()
                    if count > 0 {
                        Text("\(count)").foregroundStyle(Color.accentColor).font(.subheadline.weight(.medium))
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Multi-select picker over existing lists, binding a Set of Collection.id.
struct ListPickerSheet: View {
    let title: String
    let lists: [Collection]
    @Binding var selected: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(lists) { list in
                HStack(spacing: 12) {
                    Image(systemName: list.isDefault ? "square.grid.2x2.fill" : list.effectiveIconName)
                        .foregroundStyle(Color(hex: list.effectiveColorHex) ?? .orange)
                        .frame(width: 24)
                    Text(list.name)
                    Spacer()
                    Image(systemName: selected.contains(list.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selected.contains(list.id) ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(list.id) { selected.remove(list.id) }
                    else { selected.insert(list.id) }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selected.removeAll() }
                        .foregroundStyle(.red).disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: — Collection Detail

enum SelectionAction: String, Identifiable {
    case copy, move
    var id: String { rawValue }
}

enum GameSort: String, CaseIterable, Identifiable {
    case userRating, bggRating, bggRank, complexity, players, playtime, published, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .userRating:  "My Rating"
        case .bggRating:   "BGG Rating"
        case .bggRank:     "BGG Rank"
        case .complexity:  "Complexity"
        case .players:     "Players"
        case .playtime:    "Playtime"
        case .published:   "Published"
        case .name:        "Name"
        }
    }
    var icon: String {
        switch self {
        case .userRating:  "star.fill"
        case .bggRating:   "bgg-icon"
        case .bggRank:     "chart.bar"
        case .complexity:  "brain"
        case .players:     "person.2"
        case .playtime:    "clock"
        case .published:   "calendar"
        case .name:        "textformat.abc"
        }
    }
    var isCustomImage: Bool { self == .bggRating }
}

/// Displays the games within a specific collection, supporting sorting, filtering,
/// and batch management actions.
struct CollectionDetailView: View {
    /// The collection being viewed.
    let collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.name) private var allGames: [Game]
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]
    @State private var showAddGames = false
    @State private var showFilters = false
    @State private var filters = GameFilters()
    @State private var sortOrder: GameSort = .name
    @State private var sortAscending = true
    @State private var isSelecting = false
    @State private var selectedIds: Set<Int> = []
    @State private var pendingAction: SelectionAction?
    @State private var showEditCollection = false
    @State private var showEditRule = false
    @State private var showDeleteCollectionConfirm = false
    // Remembered app-wide so the chosen layout sticks across collections.
    @AppStorage("collectionUsesGrid") private var useGrid = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3)

    /// Membership source: derived rule set for smart lists, hand-curated games otherwise.
    private var effectiveGames: [Game] {
        collection.isSmart
            ? collection.smartGames(collections: allCollections, allGames: allGames)
            : collection.games
    }

    private var sortedGames: [Game] {
        // Ranked lists use the manual drag order; games not yet placed sort last (by name).
        if collection.isRanked {
            let pos = Dictionary(uniqueKeysWithValues: collection.rankedOrder.enumerated().map { ($1, $0) })
            return effectiveGames.sorted { a, b in
                let pa = pos[a.bggId] ?? Int.max, pb = pos[b.bggId] ?? Int.max
                return pa != pb ? pa < pb : a.name < b.name
            }
        }
        let asc = sortAscending
        return effectiveGames.sorted { a, b in
            switch sortOrder {
            case .name:        return asc ? a.name < b.name : a.name > b.name
            case .userRating:  return asc ? (a.userRating ?? 0) < (b.userRating ?? 0) : (a.userRating ?? 0) > (b.userRating ?? 0)
            case .bggRating:   return asc ? (a.rating ?? 0) < (b.rating ?? 0) : (a.rating ?? 0) > (b.rating ?? 0)
            case .bggRank:     return asc ? (a.bggRank ?? Int.max) < (b.bggRank ?? Int.max) : (a.bggRank ?? 0) > (b.bggRank ?? 0)
            case .complexity:  return asc ? (a.weight ?? 0) < (b.weight ?? 0) : (a.weight ?? 0) > (b.weight ?? 0)
            case .players:     return asc ? (a.minPlayers ?? Int.max) < (b.minPlayers ?? Int.max) : (a.minPlayers ?? 0) > (b.minPlayers ?? 0)
            case .playtime:    return asc ? (a.playtime ?? Int.max) < (b.playtime ?? Int.max) : (a.playtime ?? 0) > (b.playtime ?? 0)
            case .published:   return asc ? (a.yearPublished ?? 0) < (b.yearPublished ?? 0) : (a.yearPublished ?? 0) > (b.yearPublished ?? 0)
            }
        }
    }

    private var isDefaultSort: Bool { sortOrder == .name && sortAscending }

    private var sortDirectionLabel: String {
        switch sortOrder {
        case .name: return sortAscending ? "A → Z" : "Z → A"
        default:    return sortAscending ? "Low → High" : "High → Low"
        }
    }
    private var filteredGames: [Game] { filters.apply(sortedGames) }
    private var selectedGames: [Game] { filteredGames.filter { selectedIds.contains($0.bggId) } }
    private var otherCollections: [Collection] { allCollections.filter { $0.persistentModelID != collection.persistentModelID } }

    var body: some View {
        collectionContent
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.large)
            .safeAreaPadding(.horizontal, Spacing.screen - 16) // Adjust for List's default padding
            .toolbar(.visible, for: .navigationBar)
            .toolbar { collectionToolbar }
            .safeAreaInset(edge: .bottom) { selectionBar }
            .sheet(isPresented: $showAddGames) {
                AddGamesSheet(collection: collection, allGames: allGames)
            }
            .sheet(isPresented: $showFilters) {
                FilterView(filters: $filters, games: effectiveGames)
            }
            .sheet(isPresented: $showEditCollection) {
                RenameCollectionSheet(collection: collection, initialName: collection.name)
            }
            .sheet(isPresented: $showEditRule) {
                SmartListEditor(
                    rule: collection.decodedRule ?? SmartRule(),
                    lists: otherCollections,
                    allGames: allGames
                ) { newRule in
                    collection.setRule(newRule)
                    try? modelContext.save()
                }
            }
            .sheet(item: $pendingAction) { action in
                CollectionActionSheet(
                    action: action,
                    games: selectedGames,
                    source: collection,
                    // ponytail: smart lists derive membership from rules — games.append is ignored
                    // by smartGames(), so a move would silently lose the game. Exclude them as targets.
                    destinations: otherCollections.filter { !$0.isSmart }
                ) {
                    if action == .move { exitSelection() }
                    else { selectedIds.removeAll() }
                }
            }
            .alert("Delete \"\(collection.name)\"?", isPresented: $showDeleteCollectionConfirm) {
                Button("Delete", role: .destructive) { deleteCollection() }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var collectionContent: some View {
        Group {
            if effectiveGames.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text(
                        collection.isSmart
                            ? "No games match this smart list's rules. Tap the filter button to edit the rule."
                            : collection.isDefault
                                ? "Import from BGG or CSV to add games to your Library."
                                : "Tap ··· to add games from your Library."
                    )
                )
            } else if useGrid {
                gameGrid
            } else {
                gameList
            }
        }
    }

    private var gameList: some View {
        Group {
                List {
                    if !filters.isEmpty {
                        filterPillsBar
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    if filteredGames.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("No games match your current filters.")
                        )
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredGames, id: \.bggId) { game in
                            if isSelecting {
                                Button { toggleSelection(game) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: selectedIds.contains(game.bggId) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedIds.contains(game.bggId) ? Color.accentColor : .secondary)
                                            .font(.title3)
                                        gameRow(game)
                                    }
                                    .foregroundStyle(.primary)
                                }
                            } else {
                                NavigationLink(destination: GameDetailView(gameId: game.bggId)
                                    .toolbar(.visible, for: .navigationBar)) {
                                    HStack(spacing: 12) {
                                        if collection.isRanked { rankBadge(game) }
                                        gameRow(game)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    // Smart lists derive membership — no hand delete/move from source.
                                    if !collection.isSmart {
                                        Button(role: .destructive) {
                                            collection.games.removeAll { $0.bggId == game.bggId }
                                            try? modelContext.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        if !collection.isDefault {
                                            Button {
                                                selectedIds = [game.bggId]
                                                pendingAction = .move
                                            } label: {
                                                Label("Move", systemImage: "arrow.right.circle")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                    Button {
                                        selectedIds = [game.bggId]
                                        pendingAction = .copy
                                    } label: {
                                        Label("Copy", systemImage: "plus.square.on.square")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        .onMove(perform: moveRanked)
                    }
                }
                .listStyle(.plain)
        }
    }

    // MARK: Grid layout

    private var gameGrid: some View {
        ScrollView {
            if !filters.isEmpty {
                filterPillsBar
                    .padding(.horizontal, 4)
                    .padding(.bottom, Spacing.sm)
            }
            if filteredGames.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No games match your current filters.")
                )
                .padding(.top, Spacing.section)
            } else {
                LazyVGrid(columns: gridColumns, spacing: Spacing.lg) {
                    ForEach(filteredGames, id: \.bggId) { game in
                        gridCell(game)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func gridCell(_ game: Game) -> some View {
        if isSelecting {
            Button { toggleSelection(game) } label: { gridCard(game) }
                .buttonStyle(.plain)
        } else {
            NavigationLink(destination: GameDetailView(gameId: game.bggId)
                .toolbar(.visible, for: .navigationBar)) {
                gridCard(game)
            }
            .buttonStyle(.plain)
        }
    }

    private func gridCard(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GameCoverImage(url: URL(string: game.image ?? game.thumbnail ?? ""),
                           size: nil, cornerRadius: Radius.medium)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if collection.isRanked {
                        rankBadge(game).padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: selectedIds.contains(game.bggId) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedIds.contains(game.bggId) ? BrandAccent.color : .white)
                            .background(Circle().fill(.black.opacity(0.25)))
                            .padding(6)
                    }
                }
            Text(game.name)
                .font(Typography.metadata.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let year = game.yearPublished, year > 0 {
                Text(String(format: "%d", year))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var collectionToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { exitSelection() }
            }
        } else {
            if collection.isSmart {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditRule = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filters")
                }
            }
            if !effectiveGames.isEmpty {
                toolbarLayoutItem
                toolbarFilterItem
                toolbarSortItem
                toolbarSelectionItem
            }
            ToolbarItem(placement: .topBarTrailing) {
                collectionMenu
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarLayoutItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // Icon shows the layout you'd switch to.
            Button { useGrid.toggle() } label: {
                Image(systemName: useGrid ? "list.bullet" : "square.grid.2x2")
            }
            .accessibilityLabel(useGrid ? "List view" : "Grid view")
        }
    }

    @ToolbarContentBuilder
    private var toolbarFilterItem: some ToolbarContent {
        if !collection.isSmart {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: filters.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .foregroundStyle(filters.isEmpty ? Color.primary : Color.orange)
                .accessibilityLabel("Filters")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarSortItem: some ToolbarContent {
        if !collection.isRanked {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sortAscending.toggle() } label: {
                        Label(sortDirectionLabel, systemImage: sortAscending ? "arrow.up" : "arrow.down")
                    }
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(GameSort.allCases) { s in
                            if s.isCustomImage {
                                Label(s.label, image: s.icon).tag(s)
                            } else {
                                Label(s.label, systemImage: s.icon).tag(s)
                            }
                        }
                    }
                } label: {
                    sortIcon
                }
                .foregroundStyle(isDefaultSort ? Color.primary : Color.orange)
                .accessibilityLabel("Sort by")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarSelectionItem: some ToolbarContent {
        if !collection.isSmart {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSelecting = true } label: {
                    Image(systemName: "checklist")
                }
                .accessibilityLabel("Select games")
            }
        }
    }

    @ViewBuilder
    private var sortIcon: some View {
        if isDefaultSort {
            Image(systemName: "arrow.up.arrow.down")
        } else if sortOrder.isCustomImage {
            Image(sortOrder.icon)
        } else {
            Image(systemName: sortOrder.icon)
        }
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isSelecting {
            HStack(spacing: 16) {
                HStack(spacing: 0) {
                    Button {
                        selectedIds = Set(filteredGames.map(\.bggId))
                        pendingAction = .copy
                    } label: {
                        Text("Copy All").pillLabel(BrandAccent.color)
                    }
                    .disabled(filteredGames.isEmpty)

                    Button {
                        selectedIds = Set(filteredGames.map(\.bggId))
                        pendingAction = .move
                    } label: {
                        Text("Move All").pillLabel(BrandAccent.color)
                    }
                    .disabled(filteredGames.isEmpty || collection.isDefault)
                }
                .background(.regularMaterial, in: Capsule())

                Button {
                    selectedIds = Set(filteredGames.map(\.bggId))
                    deleteSelected()
                } label: {
                    Text("Delete All").pillLabel(.red)
                }
                .background(.regularMaterial, in: Capsule())
                .disabled(filteredGames.isEmpty)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
        }
    }

    private var collectionMenu: some View {
        Menu {
            if !collection.isDefault {
                if !collection.isSmart {
                    Button { showAddGames = true } label: {
                        Label("Add Games", systemImage: "plus")
                    }
                    Divider()
                }
                Button { showEditCollection = true } label: {
                    Label("Edit Collection", systemImage: "pencil")
                }
                Button { duplicateCollection() } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if !collection.isDefault {
                Divider()
                Button(role: .destructive) { showDeleteCollectionConfirm = true } label: {
                    Label("Delete List", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Collection actions")
    }

    /// Persists the dragged order. Only valid when unfiltered (the displayed order is the full order).
    private func moveRanked(from: IndexSet, to: Int) {
        guard collection.isRanked, filters.isEmpty else { return }
        var ids = filteredGames.map(\.bggId)
        ids.move(fromOffsets: from, toOffset: to)
        collection.rankedOrder = ids
        try? modelContext.save()
    }

    private func duplicateCollection() {
        let copy = Collection(name: "\(collection.name) copy", desc: collection.desc)
        copy.colorHex = collection.colorHex
        copy.iconName = collection.iconName
        if collection.isSmart, let rule = collection.decodedRule {
            copy.isSmart = true
            copy.setRule(rule)
        } else {
            copy.isRanked = collection.isRanked
            copy.rankedOrder = collection.rankedOrder
            LocalLibrary.add(collection.games, to: copy)
        }
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private var shareText: String {
        let lines = filteredGames.map { "• \($0.name)" }.joined(separator: "\n")
        return "\(collection.name)\n\(lines)"
    }

    private func deleteCollection() {
        modelContext.delete(collection)
        try? modelContext.save()
    }

    private func toggleSelection(_ game: Game) {
        if selectedIds.contains(game.bggId) { selectedIds.remove(game.bggId) }
        else { selectedIds.insert(game.bggId) }
    }

    private func deleteSelected() {
        collection.games.removeAll { selectedIds.contains($0.bggId) }
        try? modelContext.save()
        selectedIds.removeAll()
    }

    private func exitSelection() {
        isSelecting = false
        selectedIds.removeAll()
    }

    /// Pink position badge for ranked lists (1, 2, 3 …).
    @ViewBuilder
    private func rankBadge(_ game: Game) -> some View {
        let rank = (filteredGames.firstIndex { $0.bggId == game.bggId } ?? 0) + 1
        Text("\(rank)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.pink)
            .frame(width: 30, height: 30)
            .background(Color.pink.opacity(0.15), in: Circle())
    }

    private func gameRow(_ game: Game) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: URL(string: game.thumbnail ?? ""), size: 60, cornerRadius: 8)

            if let year = game.yearPublished, year > 0 {
                Text(game.name).bold().font(.subheadline) + Text(" (\(String(format: "%d", year)))").font(.subheadline).foregroundColor(.secondary)
            } else {
                Text(game.name).bold().font(.subheadline)
            }
        }
    }

    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !filters.titleContains.isEmpty {
                    Button { filters.titleContains = "" } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "textformat.abc").font(.caption2)
                            Text(filters.titleContains).font(.caption)
                        }
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                if !filters.languageLevels.isEmpty {
                    Button { filters.languageLevels.removeAll() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble").font(.caption2)
                            Text("\(filters.languageLevels.count)").font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(Color.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                ForEach(SetFilterField.allCases) { field in
                    if let selected = filters.setFilters[field] {
                        Button { filters.setFilters[field] = nil } label: {
                            HStack(spacing: 4) {
                                Image(systemName: field.icon).font(.caption2)
                                Text("\(selected.count)").font(.caption.monospacedDigit())
                            }
                            .foregroundStyle(field.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(field.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                ForEach(FilterField.allCases) { field in
                    if let spec = filters.specs[field] {
                        filterPill(field: field, spec: spec)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func filterPill(field: FilterField, spec: FilterSpec) -> some View {
        let symbol = spec.mode == .minimum ? "≥" : spec.mode == .maximum ? "≤" : "="
        let value = field.formatValue(spec.value) + (field.unit.map { " \($0)" } ?? "")
        return Button { filters.specs[field] = nil } label: {
            HStack(spacing: 4) {
                Image(systemName: field.icon)
                    .font(.caption2)
                Text("\(symbol) \(value)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(spec.mode.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(spec.mode.color.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: — Collection action sheet (copy / move)

struct CollectionActionSheet: View {
    let action: SelectionAction
    let games: [Game]
    let source: Collection
    let destinations: [Collection]
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(destinations) { col in
                Button(col.name) {
                    LocalLibrary.add(games, to: col)
                    if action == .move {
                        let ids = Set(games.map(\.bggId))
                        source.games.removeAll { ids.contains($0.bggId) }
                    }
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .navigationTitle(action == .copy ? "Copy to..." : "Move to...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: — Add Games from Library sheet

struct AddGamesSheet: View {
    let collection: Collection
    let allGames: [Game]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []
    @State private var searchText = ""

    private var alreadyInCollection: Set<Int> { Set(collection.games.map(\.bggId)) }

    private var candidates: [Game] {
        let eligible = allGames.filter { !alreadyInCollection.contains($0.bggId) }
        guard !searchText.isEmpty else { return eligible }
        return eligible.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(candidates, id: \.bggId) { game in
                Button {
                    if selected.contains(game.bggId) { selected.remove(game.bggId) }
                    else { selected.insert(game.bggId) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: selected.contains(game.bggId) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(game.bggId) ? Color.orange : .secondary)
                        CachedAsyncImage(url: URL(string: game.thumbnail ?? ""), size: 44, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            if let year = game.yearPublished, year > 0 {
                                Text(game.name).bold().font(.subheadline) + Text(" (\(String(format: "%d", year)))").font(.subheadline).foregroundColor(.secondary)
                            } else {
                                Text(game.name).bold().font(.subheadline)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search games")
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selected.count))") {
                        let toAdd = allGames.filter { selected.contains($0.bggId) }
                        LocalLibrary.add(toAdd, to: collection)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

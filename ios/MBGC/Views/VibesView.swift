import SwiftData
import SwiftUI

// MARK: — Collections list

private func sanitizeName(_ name: String) -> String {
    let maxLength = 50
    let sanitized = name
        .filter { $0 != "[" && $0 != "]" }
        .prefix(maxLength)
    return String(sanitized)
}

struct VibesView: View {
    let viewModel: VibesViewModel
    @Binding var path: [Collection]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var editingCollection: Collection?
    @State private var collectionToDelete: Collection?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                // Custom title — matches the large header style in design
                Text("Collection")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 4)

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
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
        HStack(spacing: 14) {
            // Icon
            collectionIcon(col)

            // Name
            Text(col.name)
                .font(.headline)

            Spacer()

            // Count — number only, no "games" label
            Text("\(col.games.count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func collectionIcon(_ col: Collection) -> some View {
        let bg: Color = col.isDefault
            ? .blue
            : Color(hex: col.effectiveColorHex) ?? .orange
        let icon = col.isDefault ? "square.grid.2x2.fill" : col.effectiveIconName
        return Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: — Shared color/icon picker (used by Create + Rename)

struct CollectionPickerBody: View {
    @Binding var name: String
    @Binding var selectedColor: String
    @Binding var selectedIcon: String

    static let colors = [
        "#3D4A52", "#8B4513", "#E040FB", "#9C27B0", "#5C35CC",
        "#2196F3", "#42A5F5", "#26C6DA", "#26A69A", "#4CAF50",
        "#66BB6A", "#FFA726", "#FF7043", "#F44336", "#EC407A",
    ]
    static let icons = [
        "list.bullet",        "person.fill",        "crown.fill",           "bolt.fill",    "star.fill",
        "face.smiling",       "face.dashed",        "flag.fill",            "sun.max.fill", "moon.fill",
        "leaf.fill",          "hand.thumbsup.fill", "hand.thumbsdown.fill", "heart.fill",   "flame.fill",
        "theatermasks.fill",  "burst.fill",         "bookmark.fill",        "checkmark",    "xmark",
        "gift.fill",          "hand.raised.fill",   "trophy.fill",          "dice.fill",    "gamecontroller.fill",
    ]

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
                }

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

private func trimmed(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: — Create sheet (own @Environment so modelContext is guaranteed)

struct CreateCollectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor = "#2196F3"
    @State private var selectedIcon = "list.bullet"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            CollectionPickerBody(name: $name, selectedColor: $selectedColor, selectedIcon: $selectedIcon)
                .navigationTitle(trimmed(name).isEmpty ? "New Collection" : trimmed(name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { save() }
                            .disabled(trimmed(name).isEmpty)
                    }
                }
                .collectionSaveAlert($errorMessage)
        }
        .presentationDetents([.large])
    }

    private func save() {
        let col = Collection(name: sanitizeName(trimmed(name)), desc: "")
        col.colorHex = selectedColor
        col.iconName = selectedIcon
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
                .navigationTitle(trimmed(name).isEmpty ? "Edit Collection" : trimmed(name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(trimmed(name).isEmpty)
                    }
                }
                .collectionSaveAlert($errorMessage)
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard !collection.isDefault else { return }
        collection.name = sanitizeName(trimmed(name))
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
}

// MARK: — Collection Detail

enum SelectionAction: String, Identifiable {
    case copy, move
    var id: String { rawValue }
}

enum GameSort: String, CaseIterable, Identifiable {
    case name, rating, complexity, players, playtime, published
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: "Name"
        case .rating: "Rating"
        case .complexity: "Complexity"
        case .players: "Players"
        case .playtime: "Playtime"
        case .published: "Published"
        }
    }
    var icon: String {
        switch self {
        case .name: "textformat.abc"
        case .rating: "star"
        case .complexity: "brain"
        case .players: "person.2"
        case .playtime: "clock"
        case .published: "calendar"
        }
    }
}

struct CollectionDetailView: View {
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
    @State private var showDeleteCollectionConfirm = false

    private var sortedGames: [Game] {
        let asc = sortAscending
        return collection.games.sorted { a, b in
            switch sortOrder {
            case .name:       return asc ? a.name < b.name : a.name > b.name
            case .rating:     return asc ? (a.rating ?? 0) < (b.rating ?? 0) : (a.rating ?? 0) > (b.rating ?? 0)
            case .complexity: return asc ? (a.weight ?? 0) < (b.weight ?? 0) : (a.weight ?? 0) > (b.weight ?? 0)
            case .players:    return asc ? (a.minPlayers ?? Int.max) < (b.minPlayers ?? Int.max) : (a.minPlayers ?? 0) > (b.minPlayers ?? 0)
            case .playtime:   return asc ? (a.playtime ?? Int.max) < (b.playtime ?? Int.max) : (a.playtime ?? 0) > (b.playtime ?? 0)
            case .published:  return asc ? (a.yearPublished ?? 0) < (b.yearPublished ?? 0) : (a.yearPublished ?? 0) > (b.yearPublished ?? 0)
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
    private var allSelected: Bool { !filteredGames.isEmpty && selectedIds.count == filteredGames.count }

    var body: some View {
        Group {
            if collection.games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text(
                        collection.isDefault
                            ? "Import from BGG or CSV to add games to your Library."
                            : "Tap ··· to add games from your Library."
                    )
                )
            } else {
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
                                    gameRow(game)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        collection.games.removeAll { $0.bggId == game.bggId }
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        selectedIds = [game.bggId]
                                        pendingAction = .move
                                    } label: {
                                        Label("Move", systemImage: "arrow.right.circle")
                                    }
                                    .tint(.orange)
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
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)

        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(allSelected ? "Deselect all" : "Select all") {
                        selectedIds = allSelected ? [] : Set(filteredGames.map(\.bggId))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { exitSelection() }
                }
            } else {
                if !collection.games.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFilters = true } label: {
                            Image(systemName: filters.isEmpty
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill")
                        }
                        .foregroundStyle(filters.isEmpty ? Color.primary : Color.orange)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { sortAscending.toggle() } label: {
                                Label(sortDirectionLabel, systemImage: sortAscending ? "arrow.up" : "arrow.down")
                            }
                            Picker("Sort By", selection: $sortOrder) {
                                ForEach(GameSort.allCases) { s in Label(s.label, systemImage: s.icon).tag(s) }
                            }
                        } label: {
                            Image(systemName: isDefaultSort ? "arrow.up.arrow.down" : sortOrder.icon)
                        }
                        .foregroundStyle(isDefaultSort ? Color.primary : Color.orange)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isSelecting = true } label: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    collectionMenu
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack {
                    HStack(spacing: 0) {
                        Button("Copy All") {
                            selectedIds = Set(filteredGames.map(\.bggId))
                            pendingAction = .copy
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 0.5, height: 20)

                        Button("Move All") {
                            selectedIds = Set(filteredGames.map(\.bggId))
                            pendingAction = .move
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .font(.body.weight(.medium))
                    .background(.regularMaterial)
                    .clipShape(Capsule())

                    Spacer()

                    Button { deleteSelected() } label: {
                        Text("Delete All")
                            .font(.body.weight(.medium))
                            .foregroundStyle(selectedIds.isEmpty ? Color.secondary : Color.red)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .disabled(selectedIds.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .sheet(isPresented: $showAddGames) {
            AddGamesSheet(collection: collection, allGames: allGames)
        }
        .sheet(isPresented: $showFilters) {
            FilterView(filters: $filters)
        }
        .sheet(isPresented: $showEditCollection) {
            RenameCollectionSheet(collection: collection, initialName: collection.name)
        }
        .sheet(item: $pendingAction) { action in
            CollectionActionSheet(
                action: action,
                games: selectedGames,
                source: collection,
                destinations: otherCollections
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

    private var collectionMenu: some View {
        Menu {
            if !collection.isDefault {
                Button { showAddGames = true } label: {
                    Label("Add Games", systemImage: "plus")
                }
                Divider()
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
            Image(systemName: "ellipsis.circle")
        }
    }

    private func duplicateCollection() {
        let copy = Collection(name: "\(collection.name) copy", desc: collection.desc)
        copy.colorHex = collection.colorHex
        copy.iconName = collection.iconName
        modelContext.insert(copy)
        LocalLibrary.add(collection.games, to: copy)
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

    private func gameRow(_ game: Game) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: game.thumbnail ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
                ForEach(FilterField.allCases) { field in
                    if let spec = filters.specs[field] {
                        filterPill(field: field, spec: spec)
                    }
                }
            }
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
                        AsyncImage(url: URL(string: game.thumbnail ?? "")) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color(.systemGray5) }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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

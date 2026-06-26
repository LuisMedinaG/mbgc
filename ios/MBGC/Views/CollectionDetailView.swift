import SwiftData
import SwiftUI

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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { showFilters = true } label: {
                            Image(systemName: filters.isEmpty
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill")
                        }
                        .foregroundStyle(filters.isEmpty ? Color.primary : Color.orange)
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
                        Button { isSelecting = true } label: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
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
            RenameCollectionSheet(collection: collection, initialName: collection.name, initialDesc: collection.desc)
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
            }
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if !collection.isDefault {
                Divider()
                Button(role: .destructive) { deleteCollection() } label: {
                    Label("Delete List", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
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

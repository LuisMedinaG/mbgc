import SwiftData
import SwiftUI

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
    @State private var haptic = 0

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
                                        if collection.isRanked { rankBadge(game) }
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
                                            haptic += 1
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
                .searchable(text: $filters.titleContains, prompt: "Search \(collection.name)")
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.selection, trigger: selectedIds)
        .sensoryFeedback(.impact(weight: .medium), trigger: haptic)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { exitSelection() }
                }
            } else {
                // Smart list: edit-rule button always visible so empty smart lists can still be configured.
                if collection.isSmart {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showEditRule = true } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Filters")
                    }
                }
                if !effectiveGames.isEmpty {
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
                    // Ranked lists are manually ordered (long-press a row to drag) — no attribute sort.
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
                                if isDefaultSort {
                                    Image(systemName: "arrow.up.arrow.down")
                                } else if sortOrder.isCustomImage {
                                    Image(sortOrder.icon)
                                } else {
                                    Image(systemName: sortOrder.icon)
                                }
                            }
                            .foregroundStyle(isDefaultSort ? Color.primary : Color.orange)
                            .accessibilityLabel("Sort by")
                        }
                    }
                    if !collection.isSmart {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { isSelecting = true } label: {
                                Image(systemName: "checklist")
                            }
                            .accessibilityLabel("Select games")
                        }
                    }
                }
                // Gap splits the action group and the ⋯ menu into separate glass capsules (iOS 26).
                // compiler(>=6.2) guard: ToolbarSpacer is an Xcode 26 SDK symbol — #available alone
                // isn't enough because older toolchains (e.g. CI's Xcode) don't declare the type at all.
                #if compiler(>=6.2)
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    collectionMenu
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack(spacing: 16) {
                    HStack(spacing: 0) {
                        Button {
                            selectedIds = Set(filteredGames.map(\.bggId))
                            pendingAction = .copy
                        } label: {
                            Text("Copy All").pillLabel(.orange)
                        }
                        .disabled(filteredGames.isEmpty)

                        Button {
                            selectedIds = Set(filteredGames.map(\.bggId))
                            pendingAction = .move
                        } label: {
                            Text("Move All").pillLabel(.orange)
                        }
                        .disabled(filteredGames.isEmpty || collection.isDefault)
                    }
                    .background(Color(.secondarySystemBackground), in: Capsule())

                    Button {
                        selectedIds = Set(filteredGames.map(\.bggId))
                        deleteSelected()
                    } label: {
                        Text("Delete All").pillLabel(.red)
                    }
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .disabled(filteredGames.isEmpty)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)
            }
        }
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
                // Smart lists derive membership from rules. games.append is ignored
                // by smartGames(), so a move would silently lose the game.
                destinations: otherCollections.filter { !$0.isSmart }
            ) {
                haptic += 1
                exitSelection()
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
        haptic += 1
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
                if field.isCustomImage {
                    Image(field.icon).font(.caption2)
                } else {
                    Image(systemName: field.icon).font(.caption2)
                }
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

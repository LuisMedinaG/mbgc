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
    @State private var editName = ""
    @State private var editDesc = ""

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                // Custom title — matches the large header style in design
                Text("Collection")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
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
                                    viewModel.delete(col, modelContext: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editName = col.name
                                    editDesc = col.desc
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
                RenameCollectionSheet(collection: col, initialName: editName, initialDesc: editDesc)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
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
        Image(systemName: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(col.isDefault ? Color.blue : Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: — Create sheet (own @Environment so modelContext is guaranteed)

struct CreateCollectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var desc = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $desc)
                }
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let sanitized = sanitizeName(trimmedName)
                        let col = Collection(name: sanitized, desc: desc)
                        modelContext.insert(col)
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            errorMessage = "Couldn't save collection."
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: — Rename sheet

struct RenameCollectionSheet: View {
    let collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var errorMessage: String?

    init(collection: Collection, initialName: String, initialDesc: String) {
        self.collection = collection
        _name = State(initialValue: initialName)
        _desc = State(initialValue: initialDesc)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $desc)
                }
            }
            .navigationTitle("Rename Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !collection.isDefault else { return }
                        collection.name = sanitizeName(trimmedName)
                        collection.desc = desc
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            errorMessage = "Couldn't save collection."
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: — Collection Detail

enum SelectionAction: String, Identifiable {
    case copy, move
    var id: String { rawValue }
}

struct CollectionDetailView: View {
    let collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.name) private var allGames: [Game]
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]
    @State private var showAddGames = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<Int> = []
    @State private var pendingAction: SelectionAction?

    private var sortedGames: [Game] { collection.games.sorted { $0.name < $1.name } }
    private var selectedGames: [Game] { sortedGames.filter { selectedIds.contains($0.bggId) } }
    private var otherCollections: [Collection] { allCollections.filter { $0.persistentModelID != collection.persistentModelID } }
    private var allSelected: Bool { !sortedGames.isEmpty && selectedIds.count == sortedGames.count }

    var body: some View {
        Group {
            if collection.games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text(
                        collection.isDefault
                            ? "Import from BGG or CSV to add games to your Library."
                            : "Tap + to add games from your Library."
                    )
                )
            } else {
                List(sortedGames, id: \.bggId) { game in
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
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        selectedIds = allSelected ? [] : Set(sortedGames.map(\.bggId))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { exitSelection() }
                }
            } else {
                if !collection.games.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") { isSelecting = true }
                    }
                }
                if !collection.isDefault {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddGames = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack(spacing: 0) {
                    Spacer()
                    Button("Copy All") { pendingAction = .copy }
                        .disabled(selectedIds.isEmpty)
                    Spacer()
                    Divider().frame(height: 20)
                    Spacer()
                    Button("Move All") { pendingAction = .move }
                        .disabled(selectedIds.isEmpty)
                    Spacer()
                    Divider().frame(height: 20)
                    Spacer()
                    Button("Delete All", role: .destructive) { deleteSelected() }
                        .disabled(selectedIds.isEmpty)
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showAddGames) {
            AddGamesSheet(collection: collection, allGames: allGames)
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

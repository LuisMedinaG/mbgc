import SwiftUI
import SwiftData

struct VibesView: View {
    let viewModel: VibesViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var editingCollection: Collection?
    @State private var editName = ""
    @State private var editDesc = ""

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "square.stack",
                        description: Text("Tap + to create your first collection.")
                    )
                } else {
                    collectionList
                }
            }
            .navigationTitle("Collection")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingCollection) { col in renameSheet(col) }
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

    private var collectionList: some View {
        List(collections) { col in
            NavigationLink(destination: CollectionDetailView(collection: col)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(col.name).font(.headline)
                        Text("\(col.games.count) game\(col.games.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if col.isDefault {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
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

    private func renameSheet(_ col: Collection) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $editName)
                TextField("Description (optional)", text: $editDesc)
            }
            .navigationTitle("Rename Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingCollection = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.update(col, name: editName, description: editDesc, modelContext: modelContext)
                        editingCollection = nil
                    }
                    .disabled(editName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: — Collection Detail

struct CollectionDetailView: View {
    let collection: Collection

    var body: some View {
        Group {
            if collection.games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text(
                        collection.isDefault
                            ? "Import a CSV to add games to your Library."
                            : "Add games to this collection from the game detail screen."
                    )
                )
            } else {
                List(collection.games, id: \.bggId) { game in
                    NavigationLink(destination: GameDetailView(gameId: game.bggId)
                        .toolbar(.visible, for: .navigationBar)) {
                        gameRow(game)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
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

            VStack(alignment: .leading, spacing: 2) {
                if let year = game.yearPublished, year > 0 {
                    Text(game.name) + Text(" (\(year))").foregroundColor(.secondary)
                } else {
                    Text(game.name)
                }
                if let rating = game.rating, rating > 0 {
                    Text(String(format: "★ %.1f", rating))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
        }
    }
}

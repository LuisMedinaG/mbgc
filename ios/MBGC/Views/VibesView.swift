import SwiftUI

struct VibesView: View {
    let viewModel: VibesViewModel
    @State private var editingCollection: Collection?
    @State private var editName = ""
    @State private var editDescription = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.collections.isEmpty {
                    ProgressView()
                } else if viewModel.collections.isEmpty {
                    ContentUnavailableView("No Collections", systemImage: "square.stack",
                        description: Text("Tap + to create your first collection."))
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
            .task { await viewModel.load() }
        }
    }

    private var collectionList: some View {
        List(viewModel.collections) { col in
            NavigationLink(destination: CollectionDetailView(collection: col)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(col.name).font(.headline)
                    Text("\(col.gameCount) game\(col.gameCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await viewModel.delete(col) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    editName = col.name
                    editDescription = col.description
                    editingCollection = col
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    private func renameSheet(_ col: Collection) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $editName)
                TextField("Description (optional)", text: $editDescription)
            }
            .navigationTitle("Rename Vibe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingCollection = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = editName
                        let desc = editDescription
                        editingCollection = nil
                        Task { await viewModel.update(col, name: name, description: desc) }
                    }
                    .disabled(editName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct CollectionDetailView: View {
    let collection: Collection
    @State private var games: [GameDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.red).padding()
            } else if games.isEmpty {
                ContentUnavailableView("No Games", systemImage: "gamecontroller",
                    description: Text("Assign this vibe to games in their detail view."))
            } else {
                List(games) { game in
                    NavigationLink(destination: GameDetailView(gameId: game.id)) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: game.thumbnail ?? "")) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.name).font(.headline)
                                if let year = game.yearPublished {
                                    Text(String(year)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            do {
                games = try await APIClient.shared.discover(collectionId: collection.id)
            } catch APIError.server(_, let message) {
                errorMessage = message
            } catch {
                errorMessage = "Couldn't load games."
            }
            isLoading = false
        }
    }
}

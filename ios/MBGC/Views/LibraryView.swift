import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.name) private var games: [Game]
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            List(games) { game in
                VStack(alignment: .leading) {
                    Text(game.name)
                    if let year = game.yearPublished {
                        Text(String(year)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Library")
            .refreshable { await viewModel.refresh(modelContext: modelContext) }
            .task { await viewModel.refresh(modelContext: modelContext) }
            .overlay {
                if games.isEmpty && viewModel.isLoading {
                    ProgressView()
                }
            }
        }
    }
}

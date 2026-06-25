import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.name) private var games: [Game]
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            List(games) { game in
                NavigationLink(value: game.id) {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: game.thumbnail ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading) {
                            Text(game.name)
                            if let year = game.yearPublished {
                                Text(String(year)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Int.self) { gameId in
                GameDetailView(gameId: gameId)
            }
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

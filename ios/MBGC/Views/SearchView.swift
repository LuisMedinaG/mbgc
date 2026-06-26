import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Game.name) private var allGames: [Game]
    @State private var query = ""
    @State private var navigationPath = NavigationPath()

    private var results: [Game] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allGames.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Search your library",
                        systemImage: "magnifyingglass",
                        description: Text("Type a game name to find it."))
                } else if results.isEmpty {
                    ContentUnavailableView("No games found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different name or keyword."))
                } else {
                    List(results) { game in
                        Button { navigationPath.append(game.bggId) } label: {
                            gameRow(game)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Board games, expansions...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Int.self) { gameId in
                GameDetailView(gameId: gameId)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
    }

    private func gameRow(_ game: Game) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: game.thumbnail ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let year = game.yearPublished, year > 0 {
                HStack(spacing: 0) {
                    Text("\(game.name) ")
                    Text("(\(year))").foregroundColor(.secondary)
                }
            } else {
                Text(game.name)
            }
        }
    }

}

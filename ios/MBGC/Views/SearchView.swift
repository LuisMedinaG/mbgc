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
        return allGames.filter { matches($0, query: q) }
    }

    /// Matches name OR any of: categories, mechanics, designers, artists, publishers.
    /// BGG metadata is local-first (post-import), so this searches the full library.
    private func matches(_ game: Game, query: String) -> Bool {
        if game.name.localizedCaseInsensitiveContains(query) { return true }
        for list in [game.categories, game.mechanics, game.designers, game.artists, game.publishers] {
            if let list, list.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                return true
            }
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("Search")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Game, mechanic, designer…")
                .navigationDestination(for: Int.self) { gameId in
                    GameDetailView(gameId: gameId)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search your library",
                systemImage: "magnifyingglass",
                description: Text("Find a game by name, mechanic, designer, or category."))
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
            .listStyle(.plain)
        }
    }

    private func gameRow(_ game: Game) -> some View {
        HStack(spacing: Spacing.md) {
            GameCoverImage(
                url: URL(string: game.thumbnail ?? game.image ?? ""),
                size: 60,
                cornerRadius: Radius.small
            )

            VStack(alignment: .leading, spacing: 2) {
                if let year = game.yearPublished, year > 0 {
                    Text("\(game.name) ") + Text("(\(year))").foregroundColor(.secondary)
                } else {
                    Text(game.name)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

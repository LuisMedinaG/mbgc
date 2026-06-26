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
            VStack(alignment: .leading, spacing: 0) {
                Text("Search")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

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
                    .listStyle(.plain)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { gameId in
                GameDetailView(gameId: gameId)
                    .toolbar(.visible, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
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
                Text("\(game.name) ") + Text("(\(year))").foregroundColor(.secondary)
            } else {
                Text(game.name)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "rectangle.stack")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.body)
                TextField("Board games, expansions…", text: $query)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .frame(height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

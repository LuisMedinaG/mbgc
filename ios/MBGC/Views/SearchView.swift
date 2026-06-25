import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GameDTO] = []
    @State private var recentGames: [GameDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Search")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                contentList
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { gameId in
                GameDetailView(gameId: gameId)
                    .toolbar(.visible, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding()
                } else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView("No games found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different name or keyword."))
                }
            }
        }
    }

    private var contentList: some View {
        let showRecent = query.isEmpty && !recentGames.isEmpty
        let showResults = !results.isEmpty

        return List {
            if showResults {
                ForEach(results) { game in gameRow(game) }
            } else if showRecent {
                Section {
                    ForEach(recentGames) { game in gameRow(game) }
                } header: {
                    HStack {
                        Text("RECENT GAMES")
                        Spacer()
                        Button("Clear") { recentGames.removeAll() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
    }

    private func gameRow(_ game: GameDTO) -> some View {
        Button { navigationPath.append(game.id) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: game.thumbnail ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.systemGray5)
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Group {
                    if let year = game.yearPublished, year > 0 {
                        Text("\(game.name) ") + Text("(\(year))").foregroundColor(.secondary)
                    } else {
                        Text(game.name)
                    }
                }
                .font(.body)
                .multilineTextAlignment(.leading)
            }
        }
        .foregroundStyle(.primary)
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
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Board games, expansions…", text: $query)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button { query = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await APIClient.shared.listGames(query: query)
            // ponytail: in-session recents only, add persistence when requested
            for game in results.prefix(3).reversed() {
                recentGames.removeAll { $0.id == game.id }
                recentGames.insert(game, at: 0)
            }
            if recentGames.count > 5 { recentGames = Array(recentGames.prefix(5)) }
        } catch {
            results = []
            errorMessage = "Search failed. Check your connection and try again."
        }
    }
}

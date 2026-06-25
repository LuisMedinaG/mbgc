import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [GameDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(results) { game in
                Button {
                    navigationPath.append(game.id)
                } label: {
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
                            if let year = game.yearPublished, year > 0 {
                                Text(String(year)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Search")
            .navigationDestination(for: Int.self) { gameId in
                GameDetailView(gameId: gameId)
            }
            .searchable(text: $query)
            .onSubmit(of: .search) { Task { await search() } }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if results.isEmpty && !query.isEmpty {
                    Text("No games found").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await APIClient.shared.listGames(query: query)
        } catch {
            results = []
            errorMessage = "Search failed. Check your connection and try again."
        }
    }
}

import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [GameDTO] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List(results) { game in
                Text(game.name)
            }
            .navigationTitle("Search")
            .searchable(text: $query)
            .onSubmit(of: .search) { Task { await search() } }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if results.isEmpty && !query.isEmpty {
                    Text("No games found").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        results = (try? await APIClient.shared.listGames(query: query)) ?? []
    }
}

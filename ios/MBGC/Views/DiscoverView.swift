import SwiftUI

struct DiscoverView: View {
    var onSearch: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Discover Coming Soon",
                systemImage: "sparkles",
                description: Text("Random picks and suggestions from your Library will appear here.")
            )
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass", action: onSearch)
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                }
            }
        }
    }
}

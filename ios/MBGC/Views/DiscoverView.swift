import SwiftUI

struct DiscoverView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Discover Coming Soon",
                systemImage: "sparkles",
                description: Text("Random picks and suggestions from your Library will appear here.")
            )
            .navigationTitle("Discover")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            VibesView()
                .tabItem { Label("Vibes", systemImage: "tag") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

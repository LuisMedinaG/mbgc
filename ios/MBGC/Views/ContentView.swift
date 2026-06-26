import SwiftData
import SwiftUI

enum HomeTab: Hashable { case discover, collection }

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var collectionsViewModel = CollectionsViewModel()
    @State private var tab: HomeTab = .discover
    @State private var collectionPath: [Collection] = []
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCreate = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            DiscoverView(
                onSearch: { showSearch = true },
                onSettings: { showSettings = true }
            )
            .tabItem { Label("Discover", systemImage: "binoculars") }
            .tag(HomeTab.discover)

            CollectionsView(
                viewModel: collectionsViewModel,
                path: $collectionPath,
                onSearch: { showSearch = true },
                onSettings: { showSettings = true },
                onCreate: { showCreate = true }
            )
            .tabItem { Label("Collection", systemImage: "square.stack") }
            .tag(HomeTab.collection)
        }
        .sheet(isPresented: $showSearch) {
            SearchView().preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings).preferredColorScheme(preferredScheme)
        }
        .sheet(isPresented: $showCreate) {
            CreateCollectionSheet().preferredColorScheme(preferredScheme)
        }
        .preferredColorScheme(preferredScheme)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCreate)
        .sensoryFeedback(.impact(weight: .light), trigger: collectionPath.count)
        .task { seedLibraryIfNeeded() }
    }

    private func seedLibraryIfNeeded() {
        guard (try? LocalLibrary.ensureDefaultCollection(in: modelContext)) != nil else { return }
        try? modelContext.save()
    }
}

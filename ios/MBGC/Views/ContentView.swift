import SwiftData
import SwiftUI

enum HomeTab { case discover, collection }

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vibesViewModel = VibesViewModel()
    @State private var tab: HomeTab = .discover
    @State private var collectionPath: [Collection] = []
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCreate = false

    var body: some View {
        Group {
            switch tab {
            case .collection: VibesView(viewModel: vibesViewModel, path: $collectionPath)
            case .discover:   LibraryView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom) {
                HomePillView(tab: $tab)
                Spacer()
                VStack(spacing: 10) {
                    if tab == .collection && collectionPath.isEmpty {
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showSearch)   { SearchView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        // CreateCollectionSheet has its own @Environment(\.modelContext) — no context capture issue
        .sheet(isPresented: $showCreate)   { CreateCollectionSheet() }
        .sensoryFeedback(.impact(weight: .medium), trigger: showCreate)
        .sensoryFeedback(.impact(weight: .light), trigger: collectionPath.count)
        .task { seedLibraryIfNeeded() }
    }

    // MARK: — Library seed

    private func seedLibraryIfNeeded() {
        guard (try? LocalLibrary.ensureDefaultCollection(in: modelContext)) != nil else { return }
        try? modelContext.save()
    }
}

struct HomePillView: View {
    @Binding var tab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            pillButton("Discover", icon: "binoculars.fill", for: .discover)
            pillButton("Collection", icon: "square.stack.fill", for: .collection)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func pillButton(_ label: String, icon: String, for target: HomeTab) -> some View {
        Button { tab = target } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2.weight(tab == target ? .semibold : .regular))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .foregroundStyle(tab == target ? Color(.systemBackground) : .secondary)
            .background(tab == target ? Color(.label) : Color.clear)
            .clipShape(Capsule())
        }
    }
}

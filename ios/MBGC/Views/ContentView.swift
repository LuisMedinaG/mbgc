import SwiftData
import SwiftUI

enum HomeTab { case discover, collection }

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vibesViewModel = VibesViewModel()
    @State private var tab: HomeTab = .discover
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCreate = false

    var body: some View {
        Group {
            switch tab {
            case .collection: VibesView(viewModel: vibesViewModel)
            case .discover:   LibraryView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom) {
                HomePillView(tab: $tab)
                Spacer()
                VStack(spacing: 10) {
                    if tab == .collection {
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
        .task { seedLibraryIfNeeded() }
    }

    // MARK: — Library seed

    private func seedLibraryIfNeeded() {
        // Fetch all + filter in memory — avoids Bool predicate issues in SwiftData
        let all = (try? modelContext.fetch(FetchDescriptor<Collection>())) ?? []
        guard !all.contains(where: { $0.isDefault }) else { return }
        let library = Collection(name: "Library", isDefault: true)
        modelContext.insert(library)
        try? modelContext.save()
    }
}

struct HomePillView: View {
    @Binding var tab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            pillButton("Discover", for: .discover)
            pillButton("Collection", for: .collection)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func pillButton(_ label: String, for target: HomeTab) -> some View {
        Button { tab = target } label: {
            Text(label)
                .font(.subheadline.weight(tab == target ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(tab == target ? Color(.systemBackground) : .secondary)
                .background(tab == target ? Color(.label) : Color.clear)
                .clipShape(Capsule())
        }
    }
}

import SwiftData
import SwiftUI

enum HomeTab { case collection, tonight }

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var vibesViewModel = VibesViewModel()
    @State private var tab: HomeTab = .tonight
    @State private var collectionPath: [Collection] = []
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCreate = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    // Hide chrome when inside a collection detail so toolbar items and bottom bar don't conflict
    private var isInDetailView: Bool { !collectionPath.isEmpty && tab == .collection }

    var body: some View {
        Group {
            switch tab {
            case .collection: VibesView(viewModel: vibesViewModel, path: $collectionPath)
            case .tonight:    FinderView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isInDetailView {
                HStack(alignment: .center) {
                    HomePillView(tab: $tab)
                    Spacer()
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(.label))
                            .frame(width: 54, height: 54)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .overlay(alignment: .top) {
                        if tab == .collection && collectionPath.isEmpty {
                            Button { showCreate = true } label: {
                                Image(systemName: "plus")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .offset(y: -62)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isInDetailView && tab != .tonight {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .padding(.top, 8)
                .padding(.trailing, 20)
            }
        }
        .sheet(isPresented: $showSearch)   { SearchView().preferredColorScheme(preferredScheme) }
        .sheet(isPresented: $showSettings) { SettingsView(isPresented: $showSettings).preferredColorScheme(preferredScheme) }
        // CreateCollectionSheet has its own @Environment(\.modelContext) — no context capture issue
        .sheet(isPresented: $showCreate)   { CreateCollectionSheet().preferredColorScheme(preferredScheme) }
        .preferredColorScheme(preferredScheme)
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
            pillButton("Collection", icon: "square.stack.fill", for: .collection)
            pillButton("Tonight", icon: "moon.stars.fill", for: .tonight)
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

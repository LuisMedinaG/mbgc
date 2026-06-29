import SwiftData
import SwiftUI

enum HomeTab { case collection, tonight }

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var vibesViewModel = VibesViewModel()
    @State private var tab: HomeTab = .tonight
    @State private var collectionPath: [Collection] = []
    @State private var finderPath: [Int] = []
    @State private var finderActive = false   // test running → hide pill/search chrome
    @State private var finderDone = false     // test complete → show pill again
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCreate = false
    @State private var createKind: CollectionKind?

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    // Hide chrome when inside a collection detail so toolbar items and bottom bar don't conflict.
    // Also hide during active finder quiz steps.
    private var isInDetailView: Bool {
        (!collectionPath.isEmpty && tab == .collection) ||
        (finderActive && !finderDone && tab == .tonight)
    }

    var body: some View {
        Group {
            switch tab {
            case .collection: VibesView(viewModel: vibesViewModel, path: $collectionPath)
            case .tonight:    FinderView(path: $finderPath, active: $finderActive, isDone: $finderDone)
            }
        }
        .overlay {
            // Tap-away to dismiss the create chooser. No dim — sits under the bottom bar/chooser.
            if showCreate {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(duration: 0.25)) { showCreate = false } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isInDetailView {
                VStack(spacing: 0) {
                    if showCreate {
                        CreateTypeChooser { kind in
                            withAnimation(.spring(duration: 0.25)) { showCreate = false }
                            createKind = kind
                        }
                        .transition(.opacity)
                    }
                    HStack(alignment: .center) {
                        HomePillView(tab: $tab)
                        Spacer()
                        HomeChromeButton(systemName: "magnifyingglass", size: 54) {
                            showSearch = true
                        }
                        .accessibilityLabel("Search")
                        // Plus floats above the search button via overlay so it adds no
                        // layout height — keeps the search button centered with the pill.
                        .overlay(alignment: .top) {
                            if tab == .collection && collectionPath.isEmpty && !showCreate {
                                Button { withAnimation(.spring(duration: 0.25)) { showCreate = true } } label: {
                                    Image(systemName: "plus")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 52, height: 52)
                                        .background(Color.accentColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .accessibilityLabel("New Collection")
                                .offset(y: -(52 + 10))
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 0)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isInDetailView && tab != .tonight {
                HomeChromeButton(systemName: "gearshape", size: 44) {
                    showSettings = true
                }
                .accessibilityLabel("Settings")
                .padding(.top, 8)
                .padding(.trailing, 20)
            }
        }
        .sheet(isPresented: $showSearch)   { SearchView().preferredColorScheme(preferredScheme) }
        .sheet(isPresented: $showSettings) { SettingsView(isPresented: $showSettings).preferredColorScheme(preferredScheme) }
        // CreateCollectionSheet has its own @Environment(\.modelContext)
        .sheet(item: $createKind) { CreateCollectionSheet(kind: $0).preferredColorScheme(preferredScheme) }
        .fullScreenCover(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } })) {
            OnboardingView { hasSeenOnboarding = true }
                .preferredColorScheme(preferredScheme)
        }
        .animation(.spring(duration: 0.25), value: showCreate)
        .preferredColorScheme(preferredScheme)
        // Note: avoid .id(appearanceMode) — it would force SwiftUI to rebuild
        // the entire view tree on theme change, wiping navigation stacks and
        // sheet state. preferredColorScheme alone is enough.
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

struct HomeChromeButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(.label))
                .frame(width: size, height: size)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }
}

struct HomePillView: View {
    @Binding var tab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            pillButton("Collection", icon: "square.stack.fill", for: .collection)
            pillButton("Tonight", icon: "moon.stars.fill", for: .tonight)
        }
        .padding(DesignSystem.Spacing.s4)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
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
            .padding(.horizontal, DesignSystem.Spacing.s20)
            .padding(.vertical, DesignSystem.Spacing.s12)
            .foregroundStyle(tab == target ? Color.accentColor : .secondary)
            .background(tab == target ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(Capsule())
        }
        .accessibilityLabel(label)
    }
}

import SwiftData
import SwiftUI

/// Root switcher: Collection tab ↔ Tonight (finder) tab.
/// Hides the floating tab bar while the user is inside a detail or quiz flow.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var vibesViewModel = VibesViewModel()
    @State private var tab: HomeTab = .tonight
    @State private var collectionPath: [Collection] = []
    @State private var finderPath: [Int] = []
    @State private var finderActive = false   // test running → hide pill/search chrome
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

    /// Bottom nav is reserved on root screens only — it disappears once the
    /// user opens a detail (Collection) or the quiz (Tonight).
    private var isInDetailView: Bool {
        (!collectionPath.isEmpty && tab == .collection) ||
        (!finderPath.isEmpty && tab == .tonight)
    }

    private var shouldShowFloatingNav: Bool {
        !isInDetailView && !finderActive
    }

    var body: some View {
        Group {
            switch tab {
            case .collection: VibesView(viewModel: vibesViewModel, path: $collectionPath)
            case .tonight:    FinderView(path: $finderPath, active: $finderActive)
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
            if shouldShowFloatingNav {
                VStack(spacing: Spacing.md) {
                    if showCreate {
                        CreateTypeChooser { kind in
                            withAnimation(.spring(duration: 0.25)) { showCreate = false }
                            createKind = kind
                        }
                        .transition(.opacity)
                    }
                    FloatingBottomNav(
                        tab: $tab,
                        onSearch: { showSearch = true },
                        onNew: {
                            // New Collection is only meaningful on the Collection tab.
                            guard tab == .collection, collectionPath.isEmpty, !showCreate else { return }
                            withAnimation(.spring(duration: 0.25)) { showCreate = true }
                        },
                        showNewButton: tab == .collection && collectionPath.isEmpty
                    )
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.sm)
            }
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowFloatingNav && tab == .collection {
                ChromeButton(systemName: "gearshape") {
                    showSettings = true
                }
                .accessibilityLabel("Settings")
                .padding(.trailing, Spacing.screen)
                // Clear the Dynamic Island / status bar on every device.
                .padding(.top, 56)
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

// MARK: — Floating bottom nav

/// Single floating control surface at the bottom of root screens.
/// Two tabs (Collection, Tonight), a search button on the trailing edge, and
/// an optional "+" overlay button on the Collection tab. Replaces the older
/// white capsule pill so the bar reads as native iOS material.
struct FloatingBottomNav: View {
    @Binding var tab: HomeTab
    let onSearch: () -> Void
    let onNew: () -> Void
    let showNewButton: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Capsule tab bar grows to fill, leaving a fixed slot for the
            // search button on the trailing edge.
            FloatingTabBar(tab: $tab)
                .frame(maxWidth: .infinity)

            ChromeButton(systemName: "magnifyingglass", size: 56, action: onSearch)
                .accessibilityLabel("Search")
                .overlay(alignment: .top) {
                    if showNewButton {
                        Button(action: onNew) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(BrandAccent.color))
                                .overlay(Circle().strokeBorder(Surface.elevated, lineWidth: 2))
                        }
                        .accessibilityLabel("New Collection")
                        .offset(y: -14)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showNewButton)
    }
}
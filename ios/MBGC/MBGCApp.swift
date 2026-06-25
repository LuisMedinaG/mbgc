import SwiftData
import SwiftUI

@main
struct MBGCApp: App {
    @State private var auth = AuthViewModel()

    init() {
        // ponytail: default URLCache.shared is ~512KB memory/10MB disk on iOS —
        // too small to keep game thumbnails across scrolls. AsyncImage uses
        // URLSession.shared, which respects this cache. Bump it instead of
        // writing a custom image loader.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
        .modelContainer(for: Game.self)
    }
}

private struct RootView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if auth.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        // ponytail: clears the local SwiftData cache whenever a session ends
        // (manual logout or expired refresh) so the next login can't see a
        // previous account's library.
        .onChange(of: auth.isAuthenticated) { wasAuthenticated, isAuthenticated in
            if wasAuthenticated && !isAuthenticated {
                try? modelContext.delete(model: Game.self)
            }
        }
    }
}

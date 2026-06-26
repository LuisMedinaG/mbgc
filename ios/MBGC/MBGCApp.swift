import SwiftData
import SwiftUI

@main
struct MBGCApp: App {
    init() {
        // ponytail: default URLCache.shared is ~512KB memory/10MB disk on iOS —
        // too small to keep game thumbnails across scrolls. AsyncImage uses
        // URLSession.shared, which respects this cache. Bump it instead of
        // writing a custom image loader.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Game.self, Collection.self])
    }
}

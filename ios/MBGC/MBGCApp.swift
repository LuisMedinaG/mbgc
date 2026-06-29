import SwiftData
import SwiftUI

@main
struct MBGCApp: App {
    // ponytail: image caching is handled by `ImageCache.shared` (see
    // `Views/CachedAsyncImage.swift`). We previously bumped the global
    // `URLCache.shared` from here, but that affected every URLSession in
    // the app — including future telemetry / crash reporter. Keep this
    // init empty until we add a real lifecycle hook.

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.indigo)
        }
        .modelContainer(for: [Game.self, Collection.self])
    }
}

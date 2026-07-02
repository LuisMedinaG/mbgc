import SwiftData
import SwiftUI

@main
struct MBGCApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Game.self, Collection.self])
    }
}

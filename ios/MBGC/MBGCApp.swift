import SwiftData
import SwiftUI

@main
struct MBGCApp: App {
    @State private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environment(auth)
        }
        .modelContainer(for: Game.self)
    }
}

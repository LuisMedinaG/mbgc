import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        NavigationStack {
            Form {
                Button("Log Out", role: .destructive) {
                    auth.logout()
                }
            }
            .navigationTitle("Settings")
        }
    }
}

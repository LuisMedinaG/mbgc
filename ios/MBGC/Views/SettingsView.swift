import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Profile") {
                        ProfileView()
                    }
                    NavigationLink("Import") {
                        ImportView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

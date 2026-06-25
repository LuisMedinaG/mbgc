import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ImportView()
                } label: {
                    Label("Import Games", systemImage: "arrow.down.circle")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

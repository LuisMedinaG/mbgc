import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ImportView()
                } label: {
                    Label("Import from BGG", systemImage: "arrow.down.circle")
                }
                NavigationLink {
                    CsvImportView()
                } label: {
                    Label("Import from CSV", systemImage: "doc.text")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

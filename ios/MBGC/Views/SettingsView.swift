import SwiftUI

struct SettingsView: View {
    @State private var showCsvImport = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ImportView()
                } label: {
                    Label("Import from BGG", systemImage: "arrow.down.circle")
                }

                Button {
                    showCsvImport = true
                } label: {
                    Label("Import from CSV", systemImage: "doc.text")
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showCsvImport) {
                NavigationStack {
                    CsvImportView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showCsvImport = false }
                            }
                        }
                }
            }
        }
    }
}

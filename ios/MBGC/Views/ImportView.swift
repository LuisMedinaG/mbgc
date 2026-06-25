import SwiftUI

struct ImportView: View {
    @State private var viewModel = ImportViewModel()

    var body: some View {
        Form {
            Section("BoardGameGeek Sync") {
                Text("Enter your BGG username in Profile, then sync your collection directly. Coming soon.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                if let err = viewModel.errorMessage {
                    Text(err).foregroundStyle(.orange).font(.caption)
                }
            }

            Section("CSV Import") {
                NavigationLink("Import from CSV") {
                    CsvImportView()
                }
                Text("Export your collection from BGG (My Collection → Export) and import the CSV file.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle("Import")
        .task { await viewModel.load() }
    }
}

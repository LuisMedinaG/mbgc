import SwiftUI

struct ImportView: View {
    @State private var viewModel = ImportViewModel()

    var body: some View {
        Form {
            Section("BoardGameGeek Sync") {
                if viewModel.hasBGGUsername {
                    Text("Syncing as \(viewModel.bggUsername)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set your BGG username in Profile first.")
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                if let result = viewModel.result {
                    HStack {
                        VStack { Text("\(result.imported)").font(.title2).fontWeight(.bold); Text("Imported").font(.caption).foregroundStyle(.secondary) }
                        VStack { Text("\(result.skipped)").font(.title2).fontWeight(.bold); Text("Skipped").font(.caption).foregroundStyle(.secondary) }
                        VStack { Text("\(result.failed.count)").font(.title2).fontWeight(.bold); Text("Failed").font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity)
                }

                Button("Sync from BGG") {
                    Task { await viewModel.sync() }
                }
                .disabled(viewModel.isSyncing || !viewModel.hasBGGUsername)
            }

            Section("CSV Import") {
                NavigationLink("Import from CSV") {
                    CsvImportView()
                }
            }
        }
        .navigationTitle("Import")
        .task { await viewModel.load() }
    }
}

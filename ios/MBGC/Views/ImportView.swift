import SwiftUI
import SwiftData

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]

    @State private var bggUsername = ""
    @State private var showCsvImport = false
    @State private var showDestinationPicker = false
    @State private var selectedGames: [Game] = []
    @State private var destinationError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // BGG Username
                VStack(alignment: .leading, spacing: 8) {
                    Text("BGG Username")
                        .font(.headline)
                    TextField("Your BoardGameGeek username", text: $bggUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Import via BGG — primary action
                VStack(spacing: 12) {
                    Button {
                        // TODO: Option A — BGG username sync
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Import from BGG")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(bggUsername.isEmpty ? Color.gray : Color.blue)
                        )
                    }
                    .disabled(bggUsername.isEmpty)

                    if bggUsername.isEmpty {
                        Text("Enter your BGG username above to sync your collection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Sync your full BGG collection — owned games, expansions, and more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Divider
                HStack {
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                }

                // Import via CSV — secondary action
                VStack(spacing: 8) {
                    Button {
                        showCsvImport = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Import from CSV")
                        }
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    }

                    Text("Export from BGG (My Collection → Export) and import the CSV file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Import from BGG")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCsvImport) {
            NavigationStack {
                CsvImportView { games in
                    selectedGames = games
                    showDestinationPicker = true
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCsvImport = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showDestinationPicker) {
            NavigationStack {
                CollectionPickerView(games: selectedGames) {
                    showDestinationPicker = false
                    showCsvImport = false
                    selectedGames = []
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: — Collection Picker

private struct CollectionPickerView: View {
    let games: [Game]
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var destinationError: String?

    var body: some View {
        List {
            Section("Add \(games.count) game\(games.count == 1 ? "" : "s") to:") {
                ForEach(collections) { col in
                    Button {
                        addToCollection(col)
                    } label: {
                        HStack {
                            Image(systemName: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
                                .foregroundStyle(col.isDefault ? .blue : .orange)
                            Text(col.name)
                            Spacer()
                            Text("\(col.games.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add to collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone() }
            }
        }
    }

    private func addToCollection(_ col: Collection) {
        col.games.append(contentsOf: games)
        do {
            try modelContext.save()
            onDone()
        } catch {
            destinationError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

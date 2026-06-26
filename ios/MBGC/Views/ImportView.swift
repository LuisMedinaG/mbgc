import SwiftData
import SwiftUI

private let bggUsernameKey = "profile.bggUsername"
private let bggLastSyncKey = "import.bgg.lastSyncDate"
private var bggToken: String? {
    let t = Bundle.main.object(forInfoDictionaryKey: "BGGToken") as? String ?? ""
    return t.isEmpty ? nil : t  // nil → BGGClient skips Authorization header; public collections still work
}
private let bggRegularImportLimit = 100
private let bggImportCooldown: TimeInterval = 7 * 24 * 60 * 60

private struct BGGImportSummary {
    let imported: Int
    let skipped: Int
    let failed: [Int]
}

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var bggUsername = ""
    @State private var showDestinationPicker = false
    @State private var selectedGames: [Game] = []
    @State private var isSyncing = false
    @State private var syncProgress: String?
    @State private var syncError: String?
    @State private var syncSummary: BGGImportSummary?
    @State private var syncLog: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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

                VStack(spacing: 12) {
                    Button {
                        Task { await importFromBGG() }
                    } label: {
                        HStack {
                            if isSyncing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(isSyncing ? "Importing from BGG" : "Import from BGG")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(!canImportBGG || isSyncing ? Color.gray : Color.blue)
                        )
                    }
                    .disabled(!canImportBGG || isSyncing)

                    if !canImportBGG {
                        Text("Enter your BGG username to sync your collection")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Sync up to \(bggRegularImportLimit) new owned games. Available once every 7 days.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if let syncProgress {
                        Text(syncProgress).font(.caption).foregroundStyle(.secondary)
                    }
                    if let syncError {
                        Text(syncError).font(.caption).foregroundStyle(.red)
                    }
                    if let syncSummary {
                        Text("Imported \(syncSummary.imported) · Skipped \(syncSummary.skipped) · Failed \(syncSummary.failed.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !syncLog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(syncLog.enumerated()), id: \.offset) { _, message in
                                Label(message, systemImage: "circle.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Import from BGG")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            bggUsername = UserDefaults.standard.string(forKey: bggUsernameKey) ?? ""
        }
        .sheet(isPresented: $showDestinationPicker) {
            NavigationStack {
                CollectionPickerView(games: selectedGames) {
                    showDestinationPicker = false
                    selectedGames = []
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var canImportBGG: Bool {
        !bggUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func importFromBGG() async {
        let username = bggUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = bggToken  // nil when not configured — BGGClient will omit the auth header
        guard !username.isEmpty else { return }
        if let message = cooldownMessage() {
            syncError = message; syncLog = [message]; return
        }

        isSyncing = true
        syncProgress = "Fetching BGG collection…"
        syncError = nil; syncSummary = nil; syncLog = []; selectedGames = []
        defer { isSyncing = false; syncProgress = nil }

        do {
            appendSyncLog("Saving BGG username")
            UserDefaults.standard.set(username, forKey: bggUsernameKey)

            appendSyncLog("Fetching owned BGG IDs")
            let bggIds = try await BGGClient.shared.fetchCollection(username: username, token: token)
            appendSyncLog("Found \(bggIds.count) owned item\(bggIds.count == 1 ? "" : "s")")

            appendSyncLog("Checking local library")
            let existing = LocalLibrary.existingBggIds(in: modelContext, from: bggIds)
            let newIds = bggIds.filter { !existing.contains($0) }
            let toFetch = Array(newIds.prefix(bggRegularImportLimit))
            let overLimit = max(0, newIds.count - toFetch.count)
            appendSyncLog("Skipping \(existing.count) already-local game\(existing.count == 1 ? "" : "s")")
            if overLimit > 0 { appendSyncLog("Limiting this sync to \(bggRegularImportLimit) new games") }

            guard !toFetch.isEmpty else {
                syncSummary = BGGImportSummary(imported: 0, skipped: existing.count, failed: [])
                syncError = bggIds.isEmpty ? "No owned games found for this BGG username." : nil
                appendSyncLog("Nothing new to import")
                return
            }

            syncProgress = "Fetching details for \(toFetch.count) new game\(toFetch.count == 1 ? "" : "s")…"
            appendSyncLog("Fetching details for \(toFetch.count) new game\(toFetch.count == 1 ? "" : "s")")
            let bggGames = try await BGGClient.shared.fetchThings(ids: toFetch, token: token) { done, total in
                Task { @MainActor in
                    self.syncProgress = "Fetching details (\(done) of \(total))…"
                    self.appendSyncLog("Fetched details for \(done) of \(total)")
                }
            }

            let fetchedById = Dictionary(grouping: bggGames, by: \.bggId).compactMapValues(\.first)
            var newGames: [Game] = []
            var failedIds: [Int] = []
            for id in toFetch {
                if let bggGame = fetchedById[id] {
                    let game = Game(bggGame: bggGame)
                    modelContext.insert(game)
                    newGames.append(game)
                } else {
                    failedIds.append(id)
                }
            }

            let library = try LocalLibrary.ensureDefaultCollection(in: modelContext)
            LocalLibrary.add(newGames, to: library)
            appendSyncLog("Saving \(newGames.count) game\(newGames.count == 1 ? "" : "s") locally")
            try modelContext.save()
            UserDefaults.standard.set(Date(), forKey: bggLastSyncKey)
            selectedGames = newGames
            syncSummary = BGGImportSummary(imported: newGames.count, skipped: existing.count + overLimit, failed: failedIds)
            showDestinationPicker = !newGames.isEmpty
            appendSyncLog(newGames.isEmpty ? "Import finished" : "Choose a destination collection")
        } catch {
            syncError = importMessage(for: error)
            appendSyncLog(syncError ?? "Import failed")
        }
    }

    private func appendSyncLog(_ message: String) {
        guard syncLog.last != message else { return }
        syncLog.append(message)
    }

    private func importMessage(for error: Error) -> String {
        if let error = error as? BGGError {
            return error.userMessage
        }
        return "Import failed. Try again."
    }

    private func cooldownMessage(now: Date = Date()) -> String? {
        guard let lastSync = UserDefaults.standard.object(forKey: bggLastSyncKey) as? Date else { return nil }
        let nextSync = lastSync.addingTimeInterval(bggImportCooldown)
        guard nextSync > now else { return nil }
        return "BGG import is available again \(nextSync.formatted(date: .abbreviated, time: .shortened))."
    }
}

// MARK: — Collection Picker (shared by ImportView + CsvImportView)

struct CollectionPickerView: View {
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
        .alert("Couldn't save", isPresented: Binding(
            get: { destinationError != nil },
            set: { if !$0 { destinationError = nil } }
        )) {
            Button("OK") { destinationError = nil }
        } message: {
            Text(destinationError ?? "")
        }
    }

    private func addToCollection(_ col: Collection) {
        LocalLibrary.add(games, to: col)
        do {
            try modelContext.save()
            onDone()
        } catch {
            destinationError = "Couldn't save collection."
        }
    }
}

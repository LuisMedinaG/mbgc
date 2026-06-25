import SwiftUI
import SwiftData

private let bggUsernameKey = "profile.bggUsername"
private let bggTokenKey = "bgg.apiToken"
private let bggLastSyncKey = "import.bgg.lastSyncDate"
private let bggRegularImportLimit = 100
private let bggImportCooldown: TimeInterval = 7 * 24 * 60 * 60

private struct BGGImportSummary {
    let imported: Int
    let skipped: Int
    let failed: [Int]
}

private enum ImportMethod {
    case bgg, csv
}

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMethod: ImportMethod = .bgg
    @State private var bggUsername = ""
    @State private var bggToken = ""
    @State private var showDestinationPicker = false
    @State private var selectedGames: [Game] = []
    @State private var isSyncing = false
    @State private var syncProgress: String?
    @State private var syncError: String?
    @State private var syncSummary: BGGImportSummary?
    @State private var syncLog: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            importMethodPicker
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if selectedMethod == .bgg {
                bggImportContent
            } else {
                CsvImportView { games in
                    selectedGames = games
                    showDestinationPicker = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(selectedMethod == .bgg ? "Import from BGG" : "Import from CSV")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            bggUsername = UserDefaults.standard.string(forKey: bggUsernameKey) ?? ""
            bggToken = Keychain.get(bggTokenKey) ?? ""
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

    private var importMethodPicker: some View {
        HStack(spacing: 12) {
            methodButton("BGG", systemImage: "arrow.down.circle.fill", method: .bgg)
            methodButton("CSV", systemImage: "doc.text.fill", method: .csv)
        }
    }

    private func methodButton(_ title: String, systemImage: String, method: ImportMethod) -> some View {
        Button {
            selectedMethod = method
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(selectedMethod == method ? Color.blue : Color(.secondarySystemBackground))
                )
                .foregroundStyle(selectedMethod == method ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var bggImportContent: some View {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("BGG API Token")
                        .font(.headline)
                    SecureField("Paste your BGG API token", text: $bggToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Stored in iOS Keychain. Do not save this token in a project file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await importFromBGG() }
                    } label: {
                        HStack {
                            if isSyncing {
                                ProgressView()
                                    .tint(.white)
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
                        Text("Enter your BGG username and API token to sync your collection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Sync up to 100 new owned games. Available once every 7 days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let syncProgress {
                        Text(syncProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let syncError {
                        Text(syncError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let syncSummary {
                        Text("Imported \(syncSummary.imported) · Skipped \(syncSummary.skipped) · Failed \(syncSummary.failed.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !syncLog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(syncLog.enumerated()), id: \.offset) { _, message in
                                Label(message, systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
    }

    private var canImportBGG: Bool {
        !bggUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bggToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func importFromBGG() async {
        let username = bggUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = bggToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !token.isEmpty else { return }
        if let message = cooldownMessage() {
            syncError = message
            syncLog = [message]
            return
        }

        isSyncing = true
        syncProgress = "Fetching BGG collection…"
        syncError = nil
        syncSummary = nil
        syncLog = []
        selectedGames = []
        defer {
            isSyncing = false
            syncProgress = nil
        }

        do {
            appendSyncLog("Saving BGG credentials")
            // bgg-import.SECURITY.1, bgg-import.SECURITY.4
            UserDefaults.standard.set(username, forKey: bggUsernameKey)
            Keychain.set(token, key: bggTokenKey)

            appendSyncLog("Fetching owned BGG IDs")
            // bgg-import.SYNC.1, bgg-import.SYNC.4, bgg-import.SECURITY.2
            let bggIds = try await BGGClient.shared.fetchCollection(username: username, token: token)
            appendSyncLog("Found \(bggIds.count) owned item\(bggIds.count == 1 ? "" : "s")")

            appendSyncLog("Checking local library")
            let existing = existingBggIds(from: bggIds)
            let newIds = bggIds.filter { !existing.contains($0) }
            let toFetch = Array(newIds.prefix(bggRegularImportLimit))
            let overLimit = max(0, newIds.count - toFetch.count)
            appendSyncLog("Skipping \(existing.count) already-local game\(existing.count == 1 ? "" : "s")")
            if overLimit > 0 {
                appendSyncLog("Limiting this sync to \(bggRegularImportLimit) new games")
            }

            guard !toFetch.isEmpty else {
                UserDefaults.standard.set(Date(), forKey: bggLastSyncKey)
                syncSummary = BGGImportSummary(imported: 0, skipped: existing.count, failed: [])
                syncError = bggIds.isEmpty ? "No owned games found for this BGG username." : nil
                appendSyncLog("Nothing new to import")
                return
            }

            syncProgress = "Fetching details for \(toFetch.count) new game\(toFetch.count == 1 ? "" : "s")…"
            appendSyncLog("Fetching details for \(toFetch.count) new game\(toFetch.count == 1 ? "" : "s")")
            let bggGames = try await BGGClient.shared.fetchThings(ids: toFetch, token: token) { done, total in
                Task { @MainActor in
                    syncProgress = "Fetching details (\(done) of \(total))…"
                    appendSyncLog("Fetched details for \(done) of \(total)")
                }
            }

            let fetchedById = Dictionary(grouping: bggGames, by: \.bggId).compactMapValues(\.first)
            var newGames: [Game] = []
            var failedIds: [Int] = []

            // bgg-import.SYNC.2, bgg-import.LIMITS.1
            for id in toFetch {
                if let bggGame = fetchedById[id] {
                    let game = Game(bggGame: bggGame)
                    modelContext.insert(game)
                    newGames.append(game)
                } else {
                    failedIds.append(id)
                }
            }

            appendSyncLog("Saving \(newGames.count) game\(newGames.count == 1 ? "" : "s") locally")
            try modelContext.save()
            UserDefaults.standard.set(Date(), forKey: bggLastSyncKey)
            selectedGames = newGames
            syncSummary = BGGImportSummary(imported: newGames.count, skipped: existing.count + overLimit, failed: failedIds)
            showDestinationPicker = !newGames.isEmpty
            appendSyncLog(newGames.isEmpty ? "Import finished" : "Choose a destination collection")
            // ponytail: no client-side admin flag; real admin/rebuild needs authenticated backend support.
        } catch {
            syncError = importMessage(for: error)
            appendSyncLog(syncError ?? "Import failed")
        }
    }

    private func appendSyncLog(_ message: String) {
        guard syncLog.last != message else { return }
        // bgg-import.SYNC.5
        syncLog.append(message)
    }

    private func importMessage(for error: Error) -> String {
        // bgg-import.SECURITY.3
        guard case BGGError.http(status: 401) = error else {
            return "Import failed: \(error.localizedDescription)"
        }
        return "BGG rejected the API token. Check the token and try again."
    }

    private func existingBggIds(from ids: [Int]) -> Set<Int> {
        let all = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        let idSet = Set(ids)
        return Set(all.map(\.bggId).filter { idSet.contains($0) })
    }

    private func cooldownMessage(now: Date = Date()) -> String? {
        guard let lastSync = UserDefaults.standard.object(forKey: bggLastSyncKey) as? Date else { return nil }
        let nextSync = lastSync.addingTimeInterval(bggImportCooldown)
        guard nextSync > now else { return nil }
        // bgg-import.LIMITS.2
        return "BGG import is available again \(nextSync.formatted(date: .abbreviated, time: .shortened))."
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
        let existing = Set(col.games.map(\.bggId))
        // bgg-import.SYNC.3
        col.games.append(contentsOf: games.filter { !existing.contains($0.bggId) })
        do {
            try modelContext.save()
            onDone()
        } catch {
            destinationError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

import SwiftData
import SwiftUI

private func sanitizeName(_ name: String) -> String {
    let maxLength = 50
    let sanitized = name
        .filter { $0 != "[" && $0 != "]" }
        .prefix(maxLength)
    return String(sanitized)
}

private let bggLastSyncKey = "import.bgg.lastSyncDate"
private let bggCachedIdsKey = "import.bgg.cachedIds"
private var bggToken: String? {
    let t = Bundle.main.object(forInfoDictionaryKey: "BGGToken") as? String ?? ""
    return t.isEmpty ? nil : t  // nil → BGGClient skips Authorization header; public collections still work
}
#if DEBUG
private let bggRegularImportLimit = 250
#else
private let bggRegularImportLimit = 100
#endif
private let bggImportCooldown: TimeInterval = 7 * 24 * 60 * 60

private struct BGGImportSummary {
    let imported: Int
    let skipped: Int
    let failed: [Int]
}

struct ImportView: View {
    var dismissAll: (() -> Void)? = nil
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
                            Text(isSyncing ? "Importing" : "Import")
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
                                    .font(.caption).foregroundStyle(statusColor(for: message))
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
        .sheet(isPresented: $showDestinationPicker) {
            NavigationStack {
                CollectionPickerView(games: selectedGames) { confirmed in
                    showDestinationPicker = false
                    selectedGames = []
                    if confirmed { dismissAll?() }
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
        #if !DEBUG
        if let message = cooldownMessage() {
            syncError = message; syncLog = [message]; return
        }
        #endif

        isSyncing = true
        syncProgress = "Fetching BGG collection…"
        syncError = nil; syncSummary = nil; syncLog = []; selectedGames = []
        defer { isSyncing = false; syncProgress = nil }

        do {
            appendSyncLog("Fetching owned BGG IDs")
            let bggIds = try await BGGClient.shared.fetchCollection(username: username, token: token)
            UserDefaults.standard.set(bggIds, forKey: bggCachedIdsKey)
            appendSyncLog("Found \(bggIds.count) owned item\(bggIds.count == 1 ? "" : "s")")

            appendSyncLog("Checking local library")
            let existing = LocalLibrary.existingBggIds(in: modelContext, from: bggIds)
            let newIds = bggIds.filter { !existing.contains($0) }
            let toFetch = Array(newIds.prefix(bggRegularImportLimit))
            let overLimit = max(0, newIds.count - toFetch.count)
            appendSyncLog("Skipping \(existing.count) already-local game\(existing.count == 1 ? "" : "s")")
            if overLimit > 0 { appendSyncLog("Limiting this sync to \(bggRegularImportLimit) new games") }

            if bggIds.isEmpty {
                syncSummary = BGGImportSummary(imported: 0, skipped: 0, failed: [])
                syncError = "No owned games found for this BGG username."
                appendSyncLog("Nothing to import")
                return
            }

            // Fetch + insert only the genuinely-new games. Already-local games are reused.
            var newGames: [Game] = []
            var failedIds: [Int] = []
            if !toFetch.isEmpty {
                syncProgress = "Fetching details for \(toFetch.count) new game\(toFetch.count == 1 ? "" : "s")…"
                appendSyncLog("Fetching details for \(toFetch.count) new game\(toFetch.count == 1 ? "" : "s")")
                let bggGames = try await BGGClient.shared.fetchThings(ids: toFetch, token: token) { done, total in
                    Task { @MainActor in
                        self.syncProgress = "Fetching details (\(done) of \(total))…"
                        self.appendSyncLog("Fetched details for \(done) of \(total)")
                    }
                }

                let fetchedById = Dictionary(grouping: bggGames, by: \.bggId).compactMapValues(\.first)
                for id in toFetch {
                    if let bggGame = fetchedById[id] {
                        let game = Game(bggGame: bggGame)
                        modelContext.insert(game)
                        newGames.append(game)
                    } else {
                        failedIds.append(id)
                    }
                }
            }

            let library = try LocalLibrary.ensureDefaultCollection(in: modelContext)
            LocalLibrary.add(newGames, to: library)
            appendSyncLog("Saving \(newGames.count) new game\(newGames.count == 1 ? "" : "s") locally")
            try modelContext.save()
            if !newGames.isEmpty {
                UserDefaults.standard.set(Date(), forKey: bggLastSyncKey)
                UserDefaults.standard.set(bggIds, forKey: bggCachedIdsKey)
            }

            // Offer the WHOLE collection (new + already-local) to the destination picker.
            // LocalLibrary.add dedups, so adding already-present games is a no-op.
            selectedGames = LocalLibrary.games(matching: bggIds, in: modelContext)
            syncSummary = BGGImportSummary(imported: newGames.count, skipped: existing.count + overLimit, failed: failedIds)
            showDestinationPicker = !selectedGames.isEmpty
            appendSyncLog(selectedGames.isEmpty ? "Import finished" : "Choose a destination collection")
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

    private func statusColor(for message: String) -> Color {
        if message.contains("Fetched") || message.contains("Found") || message.contains("Saving") || message.contains("cached") {
            return .green
        } else if message.contains("Failed") || message.contains("Couldn't") || message.contains("error") {
            return .red
        } else if message.contains("Skipping") || message.contains("Limiting") {
            return .yellow
        }
        return .secondary
    }
}

// MARK: — Collection Picker (shared by ImportView + CsvImportView)

struct CollectionPickerView: View {
    let games: [Game]
    let onDone: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var selectedIndex: Int = 0
    @State private var destinationError: String?
    @State private var showNewCollection = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 6) {
                Text("\(games.count) game\(games.count == 1 ? "" : "s") found")
                    .font(.title2.bold())
                Text("Owned games only · No expansions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $selectedIndex) {
                ForEach(Array(collections.enumerated()), id: \.offset) { idx, col in
                    Label(col.name, systemImage: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
                        .tag(idx)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange, lineWidth: 2))
            .padding(.horizontal, 20)

            Spacer()

            Button { confirm() } label: {
                Text("Import")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.orange.opacity(0.4), radius: 12, y: 4)
            }
            .padding(.bottom, 12)
        }
        .navigationTitle("Add to collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone(false) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; showNewCollection = true } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
        .onAppear { setDefaultSelection() }
        .onChange(of: collections.count) { setDefaultSelection() }
        .alert("New Collection", isPresented: $showNewCollection) {
            TextField("Name", text: $newName)
            Button("Create") { createAndSelect() }
            Button("Cancel", role: .cancel) {}
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

    private func setDefaultSelection() {
        selectedIndex = collections.firstIndex(where: { $0.isDefault }) ?? 0
    }

    private func createAndSelect() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sanitized = sanitizeName(trimmed)
        let col = Collection(name: sanitized)
        modelContext.insert(col)
        do {
            try modelContext.save()
            // Newly created collection will appear at end of @Query results
            selectedIndex = max(0, collections.count - 1)
        } catch {
            destinationError = "Couldn't create collection."
        }
    }

    private func confirm() {
        guard selectedIndex < collections.count else { return }
        let col = collections[selectedIndex]
        LocalLibrary.add(games, to: col)
        do {
            try modelContext.save()
            onDone(true)
        } catch {
            destinationError = "Couldn't save collection."
        }
    }
}

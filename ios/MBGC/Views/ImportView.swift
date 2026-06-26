import SwiftData
import SwiftUI

private let bggUsernameKey = "profile.bggUsername"
private let bggLastSyncKey = "import.bgg.lastSyncDate"
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
            if !newGames.isEmpty { UserDefaults.standard.set(Date(), forKey: bggLastSyncKey) }

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
}

// MARK: — Collection Picker (shared by ImportView + CsvImportView)

struct CollectionPickerView: View {
    let games: [Game]
    let onDone: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var selectedId: PersistentIdentifier?
    @State private var destinationError: String?
    @State private var showNewCollection = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Add \(games.count) game\(games.count == 1 ? "" : "s") to:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(collections) { col in
                        collectionCard(col)
                    }

                    Button { newName = ""; showNewCollection = true } label: {
                        Label("New Collection", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(20)
            }

            // Confirm bar
            Button { confirm() } label: {
                Text("Add to Collection")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(selectedId == nil ? Color.gray : Color.orange)
                    )
            }
            .disabled(selectedId == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .navigationTitle("Add to collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone(false) }
            }
        }
        .onAppear {
            if selectedId == nil {
                selectedId = collections.first(where: { $0.isDefault })?.persistentModelID
                    ?? collections.first?.persistentModelID
            }
        }
        .alert("New Collection", isPresented: $showNewCollection) {
            TextField("Name", text: $newName)
            Button("Create") { createCollection() }
                .disabled(trimmedNewName.isEmpty)
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

    private func collectionCard(_ col: Collection) -> some View {
        let isSelected = selectedId == col.persistentModelID
        return Button { selectedId = col.persistentModelID } label: {
            HStack(spacing: 12) {
                Image(systemName: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(col.isDefault ? Color.blue : Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(col.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(col.games.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.orange : Color(.systemGray3))
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createCollection() {
        let col = Collection(name: trimmedNewName)
        modelContext.insert(col)
        do {
            try modelContext.save()
            selectedId = col.persistentModelID
        } catch {
            destinationError = "Couldn't create collection."
        }
    }

    private func confirm() {
        guard let selectedId,
              let col = collections.first(where: { $0.persistentModelID == selectedId })
        else { return }
        LocalLibrary.add(games, to: col)
        do {
            try modelContext.save()
            onDone(true)
        } catch {
            destinationError = "Couldn't save collection."
        }
    }
}

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
private let bggRegularImportLimit = 500
#else
private let bggRegularImportLimit = 150
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
    @Environment(\.dismiss) private var dismiss

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
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 120)

                Image("BGGPoweredBy")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 156)

                VStack(alignment: .leading, spacing: 10) {
                    Text("BoardGameGeek\nImport")
                        .font(.title.bold())
                    Text("It might take a while if your collection is big.")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                TextField("Username", text: $bggUsername)
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(.top, 12)

                statusView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 112)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await importFromBGG() }
            } label: {
                if isSyncing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canImportBGG || isSyncing)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") {
                    if let dismissAll { dismissAll() }
                    else { dismiss() }
                }
            }
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

    @ViewBuilder
    private var statusView: some View {
        if isSyncing || syncProgress != nil || syncError != nil || syncSummary != nil || !syncLog.isEmpty {
            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 10) {
                    if let syncProgress {
                        Text(syncProgress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let syncError {
                        Text(syncError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    if let syncSummary {
                        Text("Imported \(syncSummary.imported) · Skipped \(syncSummary.skipped) · Failed \(syncSummary.failed.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !syncLog.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(syncLog.enumerated()), id: \.offset) { _, message in
                                    Label(message, systemImage: "circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(statusColor(for: message))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }
            }
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
        Form {
            Section {
                Text("\(games.count) game\(games.count == 1 ? "" : "s") found")
                    .font(.headline)
                Text("Owned games only · No expansions")
                    .foregroundStyle(.secondary)
            }

            Section("Destination") {
                Picker("Collection", selection: $selectedIndex) {
                    ForEach(Array(collections.enumerated()), id: \.offset) { idx, col in
                        Label(col.name, systemImage: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
                            .tag(idx)
                    }
                }
            }
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
        .safeAreaInset(edge: .bottom) {
            Button("Import") { confirm() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(collections.isEmpty)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.background)
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

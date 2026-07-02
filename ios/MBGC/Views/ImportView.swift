import SwiftData
import SwiftUI

private let bggLastSyncKey = "import.bgg.lastSyncDate"
// nil → BGGClient skips Authorization header; public collections still work.
private let bggToken: String? = {
    let t = Bundle.main.object(forInfoDictionaryKey: "BGGToken") as? String ?? ""
    return t.isEmpty ? nil : t
}()
#if DEBUG
private let bggRegularImportLimit = 500
#else
private let bggRegularImportLimit = 150
#endif
private let bggImportCooldown: TimeInterval = 7 * 24 * 60 * 60

struct ImportView: View {
    var dismissAll: (() -> Void)? = nil
    var showCloseButton: Bool = true       // hidden when embedded in onboarding
    var autoAddToLibrary: Bool = false     // onboarding: skip picker, drop into Library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var bggUsername = ""
    @State private var showDestinationPicker = false
    @State private var selectedGames: [Game] = []
    @State private var isSyncing = false
    @State private var syncProgress: String?
    @State private var syncError: String?
    @State private var syncSummary: LocalImportSummary?
    @State private var syncLog: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            if showCloseButton {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Image("powered-by-bgg")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)

                Text("BoardGameGeek\nImport")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text("It might take a while if your collection is big.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Username", text: $bggUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .padding(.top, 8)

                Divider()

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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(syncLog.enumerated()), id: \.offset) { _, message in
                                Label(message, systemImage: statusIcon(for: message))
                                    .font(.caption).foregroundStyle(statusColor(for: message))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(maxHeight: 160)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                #if DEBUG
                Button {
                    Task { await refreshAllGameDetails() }
                } label: {
                    HStack(spacing: 6) {
                        if isSyncing { ProgressView().tint(.primary).scaleEffect(0.8) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text("Refresh All")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSyncing)
                #endif

                Button {
                    Task { await importFromBGG() }
                } label: {
                    HStack {
                        if isSyncing { ProgressView().tint(.white) }
                        Text(buttonLabel)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Capsule().fill(buttonBackground))
                }
                .disabled(!canImportBGG || isSyncing || isInCooldown)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
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

    /// True when the 7-day cooldown still applies. In DEBUG the cooldown is
    /// skipped - the user can re-sync freely.
    private var isInCooldown: Bool {
        #if DEBUG
        return false
        #else
        return nextAvailableDate != nil
        #endif
    }

    /// Next sync time, or nil if cooldown has elapsed / never synced.
    private var nextAvailableDate: Date? {
        guard let lastSync = UserDefaults.standard.object(forKey: bggLastSyncKey) as? Date else { return nil }
        let next = lastSync.addingTimeInterval(bggImportCooldown)
        return next > Date() ? next : nil
    }

    private var buttonLabel: String {
        if isSyncing { return "Importing" }
        if isInCooldown, let next = nextAvailableDate {
            let days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: next).day ?? 1)
            return days == 1 ? "Available tomorrow" : "Available in \(days) days"
        }
        return "Import"
    }

    private var buttonBackground: Color {
        (!canImportBGG || isSyncing || isInCooldown) ? Color.gray : Color.accentColor
    }

    private func importFromBGG() async {
        let username = bggUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = bggToken  // nil when not configured - BGGClient will omit the auth header
        guard !username.isEmpty else { return }
        #if !DEBUG
        if let message = cooldownMessage() {
            syncError = message; syncLog = [message]; return
        }
        #endif

        isSyncing = true
        syncProgress = "Fetching BGG collection..."
        syncError = nil; syncSummary = nil; syncLog = []; selectedGames = []
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            isSyncing = false; syncProgress = nil
            let d = clock.now - start
            let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            appendSyncLog(String(format: "Finished in %.1fs", secs))
        }

        do {
            appendSyncLog("Fetching owned BGG IDs")
            let collectionResult = try await BGGClient.shared.fetchCollection(username: username, token: token)
            let plan = LocalImportService.planImport(ids: collectionResult.ids, limit: bggRegularImportLimit, in: modelContext)
            let bggIds = plan.allIds
            appendSyncLog("Found \(bggIds.count) owned item\(bggIds.count == 1 ? "" : "s")")

            appendSyncLog("Checking local library")
            appendSyncLog("Skipping \(plan.existingIds.count) already-local game\(plan.existingIds.count == 1 ? "" : "s")")
            if plan.overLimit > 0 { appendSyncLog("Limiting this sync to \(bggRegularImportLimit) new games") }

            if bggIds.isEmpty {
                syncSummary = LocalImportSummary(imported: 0, skipped: 0, failed: [])
                syncError = "No owned games found for this BGG username."
                appendSyncLog("Nothing to import")
                return
            }

            var result = LocalImportResult(
                summary: LocalImportSummary(imported: 0, skipped: plan.skipped, failed: []),
                newGames: []
            )
            if !plan.idsToFetch.isEmpty {
                syncProgress = "Fetching details for \(plan.idsToFetch.count) new game\(plan.idsToFetch.count == 1 ? "" : "s")..."
                appendSyncLog("Fetching details for \(plan.idsToFetch.count) new game\(plan.idsToFetch.count == 1 ? "" : "s")")
                let bggGames = try await BGGClient.shared.fetchThings(ids: plan.idsToFetch, token: token, userRatings: collectionResult.userRatings, wantToPlay: collectionResult.wantToPlay, numberOfPlays: collectionResult.numberOfPlays) { done, total in
                    Task { @MainActor in
                        self.syncProgress = "Fetching details (\(done) of \(total))..."
                        self.appendSyncLog("Fetched details for \(done) of \(total)")
                    }
                }

                result = try LocalImportService.saveFetchedGames(
                    bggGames,
                    requestedIds: plan.idsToFetch,
                    skipped: plan.skipped,
                    in: modelContext
                )
            } else {
                try modelContext.save()
            }

            appendSyncLog("Saving \(result.newGames.count) new game\(result.newGames.count == 1 ? "" : "s") locally")
            if !result.newGames.isEmpty {
                UserDefaults.standard.set(Date(), forKey: bggLastSyncKey)
            }

            // Offer the WHOLE collection (new + already-local) to the destination picker.
            // LocalLibrary.add dedups, so adding already-present games is a no-op.
            selectedGames = LocalLibrary.games(matching: bggIds, in: modelContext)
            syncSummary = result.summary
            if autoAddToLibrary {
                if !selectedGames.isEmpty, let library = try? LocalLibrary.ensureDefaultCollection(in: modelContext) {
                    LocalLibrary.add(selectedGames, to: library)
                    try? modelContext.save()
                }
                appendSyncLog("Added to Library")
                dismissAll?()
            } else {
                showDestinationPicker = !selectedGames.isEmpty
                appendSyncLog(selectedGames.isEmpty ? "Import finished" : "Choose a destination collection")
            }
        } catch {
            syncError = importMessage(for: error)
            appendSyncLog(syncError ?? "Import failed")
        }
    }

    #if DEBUG
    private func refreshAllGameDetails() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncProgress = "Loading local games..."
        syncError = nil; syncSummary = nil; syncLog = []
        defer { isSyncing = false; syncProgress = nil }

        do {
            let allGames = try modelContext.fetch(FetchDescriptor<Game>())
            guard !allGames.isEmpty else {
                syncError = "No games in library to refresh."
                appendSyncLog("Nothing to refresh")
                return
            }

            // Preserve user-specific fields - these come from the collection endpoint, not thing endpoint.
            let existingRatings = Dictionary(uniqueKeysWithValues: allGames.compactMap { g in g.userRating.map { (g.bggId, $0) } })
            let existingWantToPlay = Dictionary(uniqueKeysWithValues: allGames.compactMap { g in g.wantToPlay ? Optional((g.bggId, true)) : nil })
            let existingPlays = Dictionary(uniqueKeysWithValues: allGames.compactMap { g in g.numberOfPlays.map { (g.bggId, $0) } })

            let allIds = allGames.map(\.bggId)
            appendSyncLog("Refreshing \(allIds.count) game\(allIds.count == 1 ? "" : "s") from BGG")

            let bggGames = try await BGGClient.shared.fetchThings(
                ids: allIds,
                token: bggToken,
                userRatings: existingRatings,
                wantToPlay: existingWantToPlay,
                numberOfPlays: existingPlays
            ) { done, total in
                Task { @MainActor in self.syncProgress = "Refreshing (\(done) of \(total))..." }
            }

            let byId = Dictionary(grouping: bggGames, by: \.bggId).compactMapValues(\.first)
            var updated = 0
            for game in allGames {
                if let fresh = byId[game.bggId] { game.update(from: fresh); updated += 1 }
            }

            try modelContext.save()
            appendSyncLog("Refreshed \(updated) of \(allIds.count) game\(allIds.count == 1 ? "" : "s")")
        } catch {
            syncError = importMessage(for: error)
            appendSyncLog(syncError ?? "Refresh failed")
        }
    }
    #endif

    private func appendSyncLog(_ message: String) {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty, syncLog.last != message else { return }
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

    private func statusIcon(for message: String) -> String {
        if message.contains("Failed") || message.contains("Couldn't") || message.contains("error") {
            return "xmark.circle.fill"
        } else if message.contains("Skipping") || message.contains("Limiting") {
            return "exclamationmark.triangle.fill"
        } else if message.contains("Finished") || message.contains("Added") {
            return "checkmark.circle.fill"
        }
        return "circle.fill"
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

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum CSVStep {
    case upload, preview, importing, done
}

struct CsvImportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var step: CSVStep = .upload
    @State private var selectedFile: URL?
    @State private var previewRows: [BGGCSVRow] = []
    @State private var previewError: String?
    @State private var importProgress: (done: Int, total: Int)?
    @State private var importResult: LocalImportSummary?
    @State private var importError: String?
    @State private var showingPicker = false
    @State private var importedGames: [Game] = []
    @State private var showDestinationPicker = false

    var body: some View {
        Form {
            switch step {
            case .upload:   uploadContent
            case .preview:  previewContent
            case .importing: importingContent
            case .done:     doneContent
            }
        }
        .navigationTitle("Import from CSV")
        .sheet(isPresented: $showDestinationPicker) {
            NavigationStack {
                CollectionPickerView(games: importedGames) { _ in
                    showDestinationPicker = false
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText]
        ) { result in
            switch result {
            case .success(let url): selectedFile = url
            case .failure:         previewError = "Couldn't read file"
            }
        }
    }

    // MARK: — Upload step

    private var uploadContent: some View {
        Group {
            Section {
                Text("Export your collection from BoardGameGeek (My Collection → Export) and upload the CSV here.")
                    .foregroundStyle(.secondary)
                if let url = selectedFile {
                    Label(url.lastPathComponent, systemImage: "doc.text")
                        .font(.subheadline)
                }
                Button("Choose CSV File") { showingPicker = true }
            }
            Section {
                Button("Preview") { Task { await previewCSV() } }
                    .disabled(selectedFile == nil)
                if let error = previewError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    // MARK: — Preview step

    private var previewContent: some View {
        Group {
            Section {
                Text("\(previewRows.count) game\(previewRows.count == 1 ? "" : "s") found")
                    .foregroundStyle(.secondary)
                if let importError {
                    Text(importError).foregroundStyle(.red).font(.caption)
                }
            }
            Section {
                ForEach(previewRows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).lineLimit(1)
                        Text("BGG #\(row.bggId)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Import \(previewRows.count) games") { Task { await importCSV() } }
                    .disabled(previewRows.isEmpty)
                Button("Cancel") { reset() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: — Importing step

    private var importingContent: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                if let progress = importProgress {
                    Text("Fetching from BGG (\(progress.done) of \(progress.total))…")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Fetching from BGG…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: — Done step

    private var doneContent: some View {
        Group {
            if let result = importResult {
                Section {
                    HStack {
                        Spacer()
                        statCell(value: result.imported, label: "Imported")
                        Spacer()
                        statCell(value: result.skipped, label: "Skipped")
                        Spacer()
                        statCell(value: result.failed.count, label: "Failed")
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                if !result.failed.isEmpty {
                    Section("Failed IDs") {
                        Text(result.failed.map(String.init).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !importedGames.isEmpty {
                    Section {
                        Button("Add to a collection…") {
                            showDestinationPicker = true
                        }
                    }
                }
                Section {
                    Button("Import another file") { reset() }
                }
            }
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2).fontWeight(.bold)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: — Logic

    private func previewCSV() async {
        guard let url = selectedFile else { return }
        previewError = nil

        do {
            guard url.startAccessingSecurityScopedResource() else {
                previewError = "Couldn't access file — try again"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let raw = try String(contentsOf: url, encoding: .utf8)
            let rows = BGGCSVParser.parse(raw)
            if rows.isEmpty {
                previewError = "No BGG game IDs found. Make sure the CSV has an \"objectid\" column."
                return
            }
            previewRows = rows
            step = .preview
        } catch {
            previewError = "Couldn't read file: \(error.localizedDescription)"
        }
    }

    private func importCSV() async {
        guard !previewRows.isEmpty else { return }
        step = .importing
        importError = nil
        importProgress = nil
        importedGames = []

        do {
            let allIds = LocalImportService.uniqueIds(previewRows.map(\.bggId))
            let existing = LocalLibrary.existingBggIds(in: modelContext, from: allIds)
            let toFetch = allIds.filter { !existing.contains($0) }
            let skipped = allIds.count - toFetch.count

            if toFetch.isEmpty {
                importResult = LocalImportSummary(imported: 0, skipped: skipped, failed: [])
                step = .done
                return
            }

            importProgress = (done: 0, total: toFetch.count)

            let games = try await BGGClient.shared.fetchThings(ids: toFetch) { done, total in
                Task { @MainActor in
                    importProgress = (done: done, total: total)
                }
            }

            let result = try LocalImportService.saveFetchedGames(
                games,
                requestedIds: toFetch,
                skipped: skipped,
                in: modelContext
            )

            importedGames = result.newGames
            importResult = result.summary
            step = .done
        } catch {
            importError = (error as? BGGError)?.userMessage ?? "Import failed. Try again."
            step = .preview
        }
    }

    private func reset() {
        step = .upload
        selectedFile = nil
        previewRows = []
        previewError = nil
        importProgress = nil
        importResult = nil
        importError = nil
        importedGames = []
    }
}

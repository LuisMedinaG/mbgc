import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum CSVStep {
    case upload, preview, importing, done
}

private struct ImportResult {
    let imported: Int
    let skipped: Int
    let failed: [Int]
}

private struct CSVRow: Identifiable {
    let bggId: Int
    let name: String
    var id: Int { bggId }
}

struct CsvImportView: View {
    @Environment(\.modelContext) private var modelContext

    /// Called with imported Game objects after the user picks a destination.
    var onComplete: (([Game]) -> Void)?

    @State private var step: CSVStep = .upload
    @State private var selectedFile: URL?
    @State private var previewRows: [CSVRow] = []
    @State private var previewError: String?
    @State private var importProgress: (done: Int, total: Int)?
    @State private var importResult: ImportResult?
    @State private var importError: String?
    @State private var showingPicker = false
    @State private var importedGames: [Game] = []

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
                            onComplete?(importedGames)
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
            let rows = parseCSV(raw)
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
            let allIds = previewRows.map(\.bggId)
            let existing = existingBggIds(from: allIds)
            let toFetch = allIds.filter { !existing.contains($0) }
            let skipped = allIds.count - toFetch.count

            if toFetch.isEmpty {
                importResult = ImportResult(imported: 0, skipped: skipped, failed: [])
                step = .done
                return
            }

            importProgress = (done: 0, total: toFetch.count)

            let games = try await BGGClient.shared.fetchThings(ids: toFetch) { done, total in
                Task { @MainActor in
                    importProgress = (done: done, total: total)
                }
            }

            var imported = 0
            var failedIds: [Int] = []
            let fetchedById = Dictionary(grouping: games, by: \.bggId).compactMapValues(\.first)
            var newGames: [Game] = []

            for id in toFetch {
                if let bggGame = fetchedById[id] {
                    let game = Game(bggGame: bggGame)
                    modelContext.insert(game)
                    newGames.append(game)
                    imported += 1
                } else {
                    failedIds.append(id)
                }
            }
            try modelContext.save()

            importedGames = newGames
            importResult = ImportResult(imported: imported, skipped: skipped, failed: failedIds)
            step = .done
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
            step = .preview
        }
    }

    private func existingBggIds(from ids: [Int]) -> Set<Int> {
        let all = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        let idSet = Set(ids)
        return Set(all.map(\.bggId).filter { idSet.contains($0) })
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

// MARK: — CSV Parser

private func parseCSV(_ raw: String) -> [CSVRow] {
    let lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard !lines.isEmpty else { return [] }

    guard let headerIndex = lines.firstIndex(where: { $0.lowercased().contains("objectid") }) else {
        return []
    }
    let headers = csvFields(lines[headerIndex]).map { $0.lowercased() }
    guard let idCol = headers.firstIndex(of: "objectid") else { return [] }
    let nameCol = headers.firstIndex(of: "objectname")

    var rows: [CSVRow] = []
    for line in lines[(headerIndex + 1)...] {
        let fields = csvFields(line)
        guard fields.count > idCol,
              let id = Int(fields[idCol].trimmingCharacters(in: .whitespaces)),
              id > 0 else { continue }
        let name: String
        if let nc = nameCol, fields.count > nc {
            name = fields[nc].trimmingCharacters(in: .init(charactersIn: "\" \t"))
        } else {
            name = "BGG #\(id)"
        }
        rows.append(CSVRow(bggId: id, name: name.isEmpty ? "BGG #\(id)" : name))
    }
    return rows
}

private func csvFields(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    for ch in line {
        switch ch {
        case "\"": inQuotes.toggle()
        case "," where !inQuotes:
            fields.append(current)
            current = ""
        default: current.append(ch)
        }
    }
    fields.append(current)
    return fields
}

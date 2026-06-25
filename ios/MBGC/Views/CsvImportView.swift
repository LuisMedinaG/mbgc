import SwiftUI
import UniformTypeIdentifiers

enum CSVStep {
    case upload, preview, done
}

struct CsvImportView: View {
    @State private var step: CSVStep = .upload
    @State private var selectedFile: URL?
    @State private var previewRows: [CSVPreviewRow] = []
    @State private var previewTotalRows: Int = 0
    @State private var previewError: String?
    @State private var importResult: CSVImportResult?
    @State private var importError: String?
    @State private var isLoading = false
    @State private var showingPicker = false

    var body: some View {
        Form {
            switch step {
            case .upload:
                uploadContent
            case .preview:
                previewContent
            case .done:
                doneContent
            }
        }
        .navigationTitle("CSV Import")
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText]) { result in
            switch result {
            case .success(let url):
                selectedFile = url
            case .failure:
                previewError = "Couldn't read file"
            }
        }
    }

    private var uploadContent: some View {
        Group {
            Section {
                Text("Export your collection from BGG as CSV and upload it here.")
                    .foregroundStyle(.secondary)
                if let url = selectedFile {
                    Text(url.lastPathComponent)
                }
                Button("Choose CSV File") {
                    showingPicker = true
                }
            }
            Section {
                Button("Preview") {
                    Task { await previewCSV() }
                }
                .disabled(selectedFile == nil || isLoading)
                if let error = previewError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }

    private var previewContent: some View {
        Group {
            Section {
                Text("\(previewTotalRows) games in CSV")
                    .foregroundStyle(.secondary)
                let newCount = previewRows.filter { !$0.alreadyOwned }.count
                Text("\(newCount) new")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(previewRows) { row in
                    rowView(row)
                }
            }
            Section {
                let newCount = previewRows.filter { !$0.alreadyOwned }.count
                Button("Import \(newCount) games") {
                    Task { await importCSV() }
                }
                .disabled(isLoading || newCount == 0)
                Button("Cancel") {
                    reset()
                }
                .foregroundStyle(.secondary)
                if let error = importError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }

    private func rowView(_ row: CSVPreviewRow) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(row.name)
                Text("\(row.bggId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.alreadyOwned ? "owned" : "new")
                .font(.caption)
                .foregroundStyle(row.alreadyOwned ? Color.secondary : Color.green)
        }
    }

    private var doneContent: some View {
        Group {
            if let result = importResult {
                Section {
                    HStack {
                        VStack {
                            Text("\(result.imported)").font(.title).fontWeight(.bold)
                            Text("Imported").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack {
                            Text("\(result.failed)").font(.title).fontWeight(.bold)
                            Text("Failed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Section {
                    Button("Import another") {
                        reset()
                    }
                }
            }
        }
    }

    private func previewCSV() async {
        guard let url = selectedFile else { return }
        isLoading = true
        previewError = nil
        defer { isLoading = false }

        do {
            guard url.startAccessingSecurityScopedResource() else {
                previewError = "Couldn't access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let result = try await APIClient.shared.csvPreview(fileData: data, filename: url.lastPathComponent)
            previewRows = result.rows
            previewTotalRows = result.totalRows
            step = .preview
        } catch {
            previewError = "Preview failed"
        }
    }

    private func importCSV() async {
        guard !previewRows.isEmpty else { return }
        isLoading = true
        importError = nil
        defer { isLoading = false }

        let newBggIds = previewRows.filter { !$0.alreadyOwned }.map(\.bggId)
        guard !newBggIds.isEmpty else { return }

        do {
            importResult = try await APIClient.shared.csvImport(bggIds: newBggIds)
            step = .done
        } catch {
            importError = "Import failed"
        }
    }

    private func reset() {
        step = .upload
        selectedFile = nil
        previewRows = []
        previewTotalRows = 0
        previewError = nil
        importResult = nil
        importError = nil
    }
}

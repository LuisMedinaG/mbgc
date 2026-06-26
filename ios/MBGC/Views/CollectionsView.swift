import SwiftData
import SwiftUI

// MARK: — Collections list

private func sanitizeName(_ name: String) -> String {
    let maxLength = 50
    let sanitized = name
        .filter { $0 != "[" && $0 != "]" }
        .prefix(maxLength)
    return String(sanitized)
}

struct CollectionsView: View {
    let viewModel: CollectionsViewModel
    @Binding var path: [Collection]
    var onSearch: () -> Void = {}
    var onSettings: () -> Void = {}
    var onCreate: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var editingCollection: Collection?
    @State private var editName = ""
    @State private var editDesc = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "square.stack",
                        description: Text("Tap + to create your first collection.")
                    )
                } else {
                    List(collections) { col in
                        NavigationLink(value: col) {
                            collectionRow(col)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !col.isDefault {
                                Button(role: .destructive) {
                                    viewModel.delete(col, modelContext: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editName = col.name
                                    editDesc = col.desc
                                    editingCollection = col
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collection")
            .navigationDestination(for: Collection.self) { col in
                CollectionDetailView(collection: col)
                    .toolbar(.visible, for: .navigationBar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass", action: onSearch)
                    Button("New Collection", systemImage: "plus", action: onCreate)
                }
            }
            .sheet(item: $editingCollection) { col in
                RenameCollectionSheet(collection: col, initialName: editName, initialDesc: editDesc)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func collectionRow(_ col: Collection) -> some View {
        HStack(spacing: 14) {
            // Icon
            collectionIcon(col)

            // Name
            Text(col.name)
                .font(.headline)

            Spacer()

            // Count — number only, no "games" label
            Text("\(col.games.count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func collectionIcon(_ col: Collection) -> some View {
        Image(systemName: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
            .foregroundStyle(col.isDefault ? .blue : .orange)
    }
}

// MARK: — Create sheet (own @Environment so modelContext is guaranteed)

struct CreateCollectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var desc = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $desc)
                }
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let sanitized = sanitizeName(trimmedName)
                        let col = Collection(name: sanitized, desc: desc)
                        modelContext.insert(col)
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            errorMessage = "Couldn't save collection."
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: — Rename sheet

struct RenameCollectionSheet: View {
    let collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var errorMessage: String?

    init(collection: Collection, initialName: String, initialDesc: String) {
        self.collection = collection
        _name = State(initialValue: initialName)
        _desc = State(initialValue: initialDesc)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $desc)
                }
            }
            .navigationTitle("Rename Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !collection.isDefault else { return }
                        collection.name = sanitizeName(trimmedName)
                        collection.desc = desc
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            errorMessage = "Couldn't save collection."
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

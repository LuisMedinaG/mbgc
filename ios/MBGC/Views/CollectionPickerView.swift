import SwiftData
import SwiftUI

/// Shared destination picker used by BGG and CSV import flows.
/// Shows existing collections, lets the user pick one (default = Library),
/// allows inline creation of a new one, and finally adds the supplied games.
struct CollectionPickerView: View {
    let games: [Game]
    let onDone: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var selectedID: PersistentIdentifier?
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

            Picker("", selection: $selectedID) {
                ForEach(collections) { col in
                    Label(col.name, systemImage: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
                        .tag(Optional(col.persistentModelID))
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
                .accessibilityLabel("New collection")
            }
        }
        .onAppear { setDefaultSelection() }
        .onChange(of: collections.count) { setDefaultSelection() }
        .alert("New Collection", isPresented: $showNewCollection) {
            TextField("Name", text: $newName)
            Button("Create") { createAndSelect() }
            Button("Cancel", role: .cancel) {}
        }
        .errorAlert($destinationError)
    }

    private func setDefaultSelection() {
        // Keep an existing valid pick — otherwise the @Query refresh after
        // createAndSelect() would clobber the just-created collection back to Library.
        if let id = selectedID, collections.contains(where: { $0.persistentModelID == id }) {
            return
        }
        selectedID = collections.first(where: { $0.isDefault })?.persistentModelID
            ?? collections.first?.persistentModelID
    }

    private func createAndSelect() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let col = Collection(name: CollectionName.sanitize(trimmed))
        modelContext.insert(col)
        do {
            try modelContext.save()
            // Newly created collection will appear at end of @Query results;
            // select it once @Query picks it up.
            selectedID = col.persistentModelID
        } catch {
            destinationError = "Couldn't create collection."
        }
    }

    private func confirm() {
        guard let id = selectedID,
              let col = collections.first(where: { $0.persistentModelID == id }) else { return }
        LocalLibrary.add(games, to: col)
        do {
            try modelContext.save()
            onDone(true)
        } catch {
            destinationError = "Couldn't save collection."
        }
    }
}

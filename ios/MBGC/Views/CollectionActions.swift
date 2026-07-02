import SwiftData
import SwiftUI

/// Pick a destination collection when copying/moving a batch of selected games.
struct CollectionActionSheet: View {
    let action: SelectionAction
    let games: [Game]
    let source: Collection
    let destinations: [Collection]
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(destinations) { col in
                Button(col.name) {
                    LocalLibrary.add(games, to: col)
                    if action == .move {
                        let ids = Set(games.map(\.bggId))
                        source.games.removeAll { ids.contains($0.bggId) }
                    }
                    try? modelContext.save()
                    onComplete()
                    dismiss()
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .navigationTitle(action == .copy ? "Copy to..." : "Move to...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Multi-select over a user's full library — adds games not already in the
/// destination collection. Local-search box narrows the candidate list.
struct AddGamesSheet: View {
    let collection: Collection
    let allGames: [Game]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []
    @State private var searchText = ""

    private var alreadyInCollection: Set<Int> { Set(collection.games.map(\.bggId)) }

    private var candidates: [Game] {
        let eligible = allGames.filter { !alreadyInCollection.contains($0.bggId) }
        guard !searchText.isEmpty else { return eligible }
        return eligible.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(candidates, id: \.bggId) { game in
                Button {
                    if selected.contains(game.bggId) { selected.remove(game.bggId) }
                    else { selected.insert(game.bggId) }
                } label: {
                    HStack(spacing: 14) {
                        CachedAsyncImage(url: URL(string: game.thumbnail ?? ""), size: 44, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            if let year = game.yearPublished, year > 0 {
                                Text(game.name).bold().font(.subheadline) + Text(" (\(String(format: "%d", year)))").font(.subheadline).foregroundColor(.secondary)
                            } else {
                                Text(game.name).bold().font(.subheadline)
                            }
                        }
                        Spacer()
                        Image(systemName: selected.contains(game.bggId) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(game.bggId) ? Color.orange : .secondary)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search games")
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selected.count))") {
                        let toAdd = allGames.filter { selected.contains($0.bggId) }
                        LocalLibrary.add(toAdd, to: collection)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

// MARK: - Reusable pills / alerts
//
// Tiny view modifiers that keep the inline call sites readable. Lives in this
// file because the only callers today live next to the collection tab.

extension View {
    /// Selection-bar pill: tinted text on the parent capsule, no per-button bg.
    func pillLabel(_ tint: Color) -> some View {
        self.fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
    }
}

import SwiftData
import SwiftUI

/// Top-level "Collection" tab: lists every collection (Library first),
/// hands row taps off to `CollectionDetailView`, and exposes create / edit /
/// delete via swipe actions and the home "+" sheet.
struct VibesView: View {
    /// Legacy name for the view model handling collection CRUD.
    @Bindable var viewModel: VibesViewModel
    @Binding var path: [Collection]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query private var allGames: [Game]
    @State private var editingCollection: Collection?
    @State private var collectionToDelete: Collection?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                // Custom title — matches the large header style in design
                Text("Collection")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 4)

                if collections.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "square.stack",
                        description: Text("Tap + to create your first collection.")
                    )
                    Spacer()
                } else {
                    List(collections) { col in
                        NavigationLink(value: col) {
                            collectionRow(col)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !col.isDefault {
                                Button(role: .destructive) {
                                    collectionToDelete = col
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingCollection = col
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationDestination(for: Collection.self) { col in
                CollectionDetailView(collection: col)
                    .toolbar(.visible, for: .navigationBar)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingCollection) { col in
                RenameCollectionSheet(collection: col, initialName: col.name)
            }
            .errorAlert($viewModel.errorMessage)
            .alert("Delete \"\(collectionToDelete?.name ?? "")\"?", isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let col = collectionToDelete { viewModel.delete(col, modelContext: modelContext) }
                    collectionToDelete = nil
                }
                Button("Cancel", role: .cancel) { collectionToDelete = nil }
            }
        }
    }

    private func collectionRow(_ col: Collection) -> some View {
        HStack(spacing: 14) {
            collectionIcon(col)

            Text(col.name)
                .font(.headline)

            Spacer()

            // Count — number only, no "games" label
            Text("\(count(for: col))")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func count(for col: Collection) -> Int {
        col.isSmart
            ? col.smartGames(collections: collections, allGames: allGames).count
            : col.games.count
    }

    private func collectionIcon(_ col: Collection) -> some View {
        let bg: Color = col.isDefault
            ? .blue
            : Color(hex: col.effectiveColorHex) ?? .orange
        let icon = col.isDefault ? "square.grid.2x2.fill" : col.effectiveIconName
        return Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) { cornerBadge(col) }
    }

    /// Small corner badge marking smart (bolt) vs ranked (star) lists — omitted for standard lists.
    @ViewBuilder
    private func cornerBadge(_ col: Collection) -> some View {
        if col.isSmart || col.isRanked {
            Image(systemName: col.isSmart ? "bolt.fill" : "star.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(col.isSmart ? Color.purple : Color.pink)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                .offset(x: 6, y: 6)
        }
    }
}

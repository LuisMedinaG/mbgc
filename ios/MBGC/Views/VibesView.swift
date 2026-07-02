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
    @State private var editingRuleCollection: Collection?
    @State private var collectionToDelete: Collection?
    private var orderedCollections: [Collection] { Collection.ordered(collections) }

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
                    List {
                        ForEach(orderedCollections) { col in
                            NavigationLink(value: col) {
                                collectionRow(col)
                            }
                            .contextMenu {
                                collectionContextMenu(for: col)
                            }
                            .moveDisabled(col.isDefault)
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
                        .onMove(perform: moveCollections)
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
            .sheet(item: $editingRuleCollection) { col in
                SmartListEditor(
                    rule: col.decodedRule ?? SmartRule(),
                    lists: orderedCollections.filter { $0.persistentModelID != col.persistentModelID },
                    allGames: allGames
                ) { newRule in
                    col.setRule(newRule)
                    try? modelContext.save()
                }
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

    @ViewBuilder
    private func collectionContextMenu(for col: Collection) -> some View {
        if !col.isDefault {
            Button {
                editingCollection = col
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        if col.isSmart {
            Button {
                editingRuleCollection = col
            } label: {
                Label("Edit Smart Rules", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        Button {
            duplicate(col)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        ShareLink(item: shareText(for: col)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if !col.isDefault {
            Divider()
            Button(role: .destructive) {
                collectionToDelete = col
            } label: {
                Label("Delete", systemImage: "trash")
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
            ? col.smartGames(collections: orderedCollections, allGames: allGames).count
            : col.games.count
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        // local-library.COLLECTIONS.6
        let defaults = orderedCollections.filter(\.isDefault)
        let defaultCount = defaults.count
        guard source.allSatisfy({ $0 >= defaultCount }) else { return }

        var customCollections = orderedCollections.filter { !$0.isDefault }
        let adjustedSource = IndexSet(source.map { $0 - defaultCount })
        let adjustedDestination = max(0, destination - defaultCount)
        customCollections.move(fromOffsets: adjustedSource, toOffset: adjustedDestination)
        Collection.applyDisplayOrder(defaults + customCollections)
        try? modelContext.save()
    }

    private func duplicate(_ col: Collection) {
        let copy = Collection(name: "\(col.name) copy", desc: col.desc)
        copy.colorHex = col.colorHex
        copy.iconName = col.iconName
        if col.isSmart, let rule = col.decodedRule {
            copy.isSmart = true
            copy.setRule(rule)
        } else {
            copy.isRanked = col.isRanked
            copy.rankedOrder = col.rankedOrder
            LocalLibrary.add(col.games, to: copy)
        }
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func shareText(for col: Collection) -> String {
        let games = col.isSmart
            ? col.smartGames(collections: collections, allGames: allGames)
            : col.games
        let lines = games.map { "• \($0.name)" }.joined(separator: "\n")
        return "\(col.name)\n\(lines)"
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

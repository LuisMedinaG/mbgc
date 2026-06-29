import SwiftData
import SwiftUI

struct GameDetailView: View {
    let gameId: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GameDetailViewModel()
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]
    @State private var showDeleteAlert = false
    @State private var showAddToCollection = false
    @State private var isDescExpanded = false

    var body: some View {
        Group {
            if let game = viewModel.game {
                ScrollView {
                    VStack(spacing: 0) {
                        heroImage(game)
                            .ignoresSafeArea(edges: .top)
                        titleSection(game)
                        statsRow(game)
                            .padding(.horizontal, Spacing.screen)
                            .padding(.bottom, Spacing.lg)
                        descriptionSection(game)
                        tagsSection(game)
                        linksSection(game)
                        Spacer(minLength: Spacing.section)
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar(game) }
                .sheet(isPresented: $showAddToCollection) {
                    AddToCollectionSheet(game: game, allCollections: allCollections)
                }
            } else if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // Make the nav bar background visible over the hero image so the menu
        // button stays legible regardless of the artwork's lightness.
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More actions")
            }
        }
        .alert("Delete \"\(viewModel.game?.name ?? "")\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if viewModel.deleteGame(modelContext: modelContext) { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { viewModel.load(gameId: gameId, modelContext: modelContext) }
    }

    private func heroImage(_ game: Game) -> some View {
        CachedAsyncImage(url: URL(string: game.image ?? game.thumbnail ?? ""))
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipped()
    }

    private func titleSection(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(game.name)
                .font(Typography.cardTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            GameMetadataRow(
                rating: game.rating,
                minPlayers: game.minPlayers,
                maxPlayers: game.maxPlayers,
                playtime: game.playtime
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    private func statsRow(_ game: Game) -> some View {
        HStack(alignment: .top, spacing: 0) {
            statBlock(label: "Players",  value: playersStr(game))
            divider
            statBlock(label: "Playtime", value: "\(playtimeStr(game)) min")
            divider
            statBlock(label: "Weight",   value: game.weight.map { String(format: "%.1f", $0) } ?? "—")
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(Typography.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Surface.separator)
            .frame(width: 1)
            .frame(maxHeight: 36)
            .padding(.vertical, Spacing.xs)
    }

    private func descriptionSection(_ game: Game) -> some View {
        Group {
            if let desc = game.gameDescription, !desc.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(desc)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(isDescExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isDescExpanded {
                        Button("Show more") { isDescExpanded = true }
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(BrandAccent.color)
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    private func tagsSection(_ game: Game) -> some View {
        let categories = game.categories ?? []
        let mechanics = game.mechanics ?? []
        let types = game.types ?? []
        return Group {
            if !categories.isEmpty || !mechanics.isEmpty || !types.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if !types.isEmpty {
                        tagGroup(title: "Type", items: types)
                    }
                    if !categories.isEmpty {
                        tagGroup(title: "Categories", items: categories)
                    }
                    if !mechanics.isEmpty {
                        tagGroup(title: "Mechanics", items: mechanics)
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    private func tagGroup(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.cardTitle)
                .foregroundStyle(.primary)
            FlowLayout(spacing: Spacing.sm, runSpacing: Spacing.sm) {
                ForEach(items, id: \.self) { tag in
                    TagPill(text: tag)
                }
            }
        }
    }

    private func linksSection(_ game: Game) -> some View {
        VStack(spacing: Spacing.sm) {
            if let rulesUrl = game.rulesUrl, !rulesUrl.isEmpty, let url = URL(string: rulesUrl) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Rules")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.lg)
                    .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
                }
            }
            let bggId = game.bggId
            if bggId > 0 {
                Link(destination: URL(string: "https://boardgamegeek.com/boardgame/\(bggId)")!) {
                    HStack {
                        Image(systemName: "globe")
                        Text("View on BGG")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.lg)
                    .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
                }
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, Spacing.lg)
    }

    private func bottomBar(_ game: Game) -> some View {
        let nonDefaultCollections = game.collections.filter { !$0.isDefault }
        let label = nonDefaultCollections.isEmpty
            ? "Add to Collection"
            : "In \(nonDefaultCollections.count) Collection\(nonDefaultCollections.count == 1 ? "" : "s")"
        return Button { showAddToCollection = true } label: {
            Label(label, systemImage: nonDefaultCollections.isEmpty ? "plus" : "folder.fill")
                .font(Typography.bodyEmphasis)
                .foregroundStyle(.white)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(BrandAccent.color))
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.sm)
        .background(Surface.elevated.opacity(0.001))   // ensures the bar catches safe-area taps cleanly
    }

    private func playersStr(_ game: Game) -> String {
        if let min = game.minPlayers, let max = game.maxPlayers {
            return min == max ? "\(min)" : "\(min)–\(max)"
        }
        return "—"
    }

    /// "—" when BGG didn't publish a playtime — never "0" (would imply an instant game).
    private func playtimeStr(_ game: Game) -> String {
        game.playtime.map { "\($0)" } ?? "—"
    }
}

struct AddToCollectionSheet: View {
    let game: Game
    let allCollections: [Collection]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<PersistentIdentifier>

    init(game: Game, allCollections: [Collection]) {
        self.game = game
        self.allCollections = allCollections
        _selectedIds = State(initialValue: Set(game.collections.map(\.persistentModelID)))
    }

    var body: some View {
        NavigationStack {
            List(allCollections) { col in
                let isSelected = col.isDefault || selectedIds.contains(col.persistentModelID)
                Button {
                    guard !col.isDefault else { return }
                    if selectedIds.contains(col.persistentModelID) { selectedIds.remove(col.persistentModelID) }
                    else { selectedIds.insert(col.persistentModelID) }
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(col.isDefault ? Color.secondary.opacity(0.6) : Color.accentColor)
                        Text(col.name)
                            .foregroundStyle(col.isDefault ? Color.secondary : Color.primary)
                        if col.isDefault {
                            Text("Always included")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .disabled(col.isDefault)
                .accessibilityHint(col.isDefault ? "Library always contains every imported game" : "")
            }
            .listStyle(.plain)
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        game.collections = allCollections.filter { $0.isDefault || selectedIds.contains($0.persistentModelID) }
        try? modelContext.save()
        dismiss()
    }
}



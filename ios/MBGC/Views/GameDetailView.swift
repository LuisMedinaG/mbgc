import SwiftData
import SwiftUI
import UIKit

struct GameDetailView: View {
    let gameId: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GameDetailViewModel()
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]
    @State private var showDeleteAlert = false
    @State private var showAddToCollection = false
    @State private var isDescExpanded = false
    @State private var didDelete = false

    var body: some View {
        Group {
            if let game = viewModel.game {
                ScrollView {
                    VStack(spacing: 0) {
                        heroImage(game)
                            .ignoresSafeArea(edges: .top)
                        titleSection(game)
                        statsRow(game)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        descriptionSection(game)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        tagsSection(game)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        linksSection(game)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
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
                    if viewModel.game?.bggId ?? 0 > 0 {
                        ShareLink(item: bggURL) {
                            Label("Share BGG Link", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = bggURL.absoluteString
                        } label: {
                            Label("Copy BGG Link", systemImage: "doc.on.doc")
                        }
                        Divider()
                    }
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More actions")
            }
        }
        .sensoryFeedback(.warning, trigger: didDelete)
        .alert("Delete \"\(viewModel.game?.name ?? "")\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                didDelete.toggle()
                if viewModel.deleteGame(modelContext: modelContext) { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { viewModel.load(gameId: gameId, modelContext: modelContext) }
    }

    private func heroImage(_ game: Game) -> some View {
        CachedAsyncImage(url: URL(string: game.image ?? game.thumbnail ?? ""))
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipped()
    }

    private func titleSection(_ game: Game) -> some View {
        VStack(spacing: 6) {
            Text(game.name)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
            // dot-separated: year · BGG rating · age+
            let parts: [String] = [
                game.yearPublished.map { $0 > 0 ? String($0) : nil } ?? nil,
                game.rating.map { $0 > 0 ? "BGG \(String(format: "%.1f", $0))" : nil } ?? nil,
                game.minAge.map { $0 > 0 ? "\($0)+" : nil } ?? nil
            ].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func statsRow(_ game: Game) -> some View {
        HStack {
            VStack(spacing: 2) {
                Text("Players").font(.caption2).foregroundStyle(.secondary)
                Text(playersStr(game)).font(.title3).fontWeight(.bold)
                Text("count").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 2) {
                Text("Playtime").font(.caption2).foregroundStyle(.secondary)
                Text(playtimeStr(game)).font(.title3).fontWeight(.bold)
                Text("minutes").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 2) {
                Text("Weight").font(.caption2).foregroundStyle(.secondary)
                Text(game.weight.map { String(format: "%.1f", $0) } ?? "—").font(.title3).fontWeight(.bold)
                Text("complexity").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func descriptionSection(_ game: Game) -> some View {
        Group {
            if let desc = game.gameDescription, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(desc)
                        .font(.subheadline)
                        .lineLimit(isDescExpanded ? nil : 4)
                    if !isDescExpanded {
                        Button("Show more") { isDescExpanded = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    private func tagsSection(_ game: Game) -> some View {
        let categories = game.categories ?? []
        let mechanics = game.mechanics ?? []
        let types = game.types ?? []
        return Group {
            if !categories.isEmpty || !mechanics.isEmpty || !types.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !types.isEmpty {
                        Text("Type").font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(types, id: \.self) { tagChip($0, color: .indigo) }
                        }
                    }
                    if !categories.isEmpty {
                        Text("Categories").font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(categories, id: \.self) { tagChip($0, color: .blue) }
                        }
                    }
                    if !mechanics.isEmpty {
                        Text("Mechanics").font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(mechanics, id: \.self) { tagChip($0, color: .green) }
                        }
                    }
                }
            }
        }
    }

    private func tagChip(_ tag: String, color: Color) -> some View {
        Text(tag)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func linksSection(_ game: Game) -> some View {
        VStack(spacing: 8) {
            if let rulesUrl = game.rulesUrl, !rulesUrl.isEmpty, let url = URL(string: rulesUrl) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Rules")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
            let bggId = game.bggId
            if bggId > 0 {
                Link(destination: URL(string: "https://boardgamegeek.com/boardgame/\(bggId)")!) {
                    HStack {
                        Image(systemName: "gamecontroller")
                        Text("View on BGG")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func bottomBar(_ game: Game) -> some View {
        let nonDefaultCollections = game.collections.filter { !$0.isDefault }
        let label = nonDefaultCollections.isEmpty
            ? "Add to collection"
            : "In \(nonDefaultCollections.count) collection\(nonDefaultCollections.count == 1 ? "" : "s")"
        return Button { showAddToCollection = true } label: {
            Label(label, systemImage: nonDefaultCollections.isEmpty ? "plus" : "folder.fill")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: 320)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var bggURL: URL {
        URL(string: "https://boardgamegeek.com/boardgame/\(viewModel.game?.bggId ?? 0)")!
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
                        Text(col.name)
                            .foregroundStyle(col.isDefault ? Color.secondary : Color.primary)
                        if col.isDefault {
                            Text("Always included")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(col.isDefault ? Color.secondary.opacity(0.6) : Color.accentColor)
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
        .sensoryFeedback(.selection, trigger: selectedIds)
        .presentationDetents([.medium, .large])
    }

    private func save() {
        game.collections = allCollections.filter { $0.isDefault || selectedIds.contains($0.persistentModelID) }
        try? modelContext.save()
        dismiss()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0; var y: CGFloat = 0; var lineHeight: CGFloat = 0
            for subview in subviews {
                let sz = subview.sizeThatFits(.unspecified)
                if x + sz.width > width, x > 0 { x = 0; y += lineHeight + spacing; lineHeight = 0 }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, sz.height)
                x += sz.width + spacing
            }
            size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

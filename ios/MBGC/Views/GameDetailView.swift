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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.black.opacity(0.3))
                }
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
        AsyncImage(url: URL(string: game.image ?? game.thumbnail ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color(.systemGray5))
        }
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
                Text("PLAYERS").font(.caption2).foregroundStyle(.secondary)
                Text(playersStr(game)).font(.title3).fontWeight(.bold)
                Text("Players").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 2) {
                Text("PLAYTIME").font(.caption2).foregroundStyle(.secondary)
                Text("\(game.playtime ?? 0)").font(.title3).fontWeight(.bold)
                Text("Minutes").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 2) {
                Text("WEIGHT").font(.caption2).foregroundStyle(.secondary)
                Text(game.weight.map { String(format: "%.1f", $0) } ?? "—").font(.title3).fontWeight(.bold)
                Text("Complexity").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6))
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
                        Button("More...") { isDescExpanded = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func tagsSection(_ game: Game) -> some View {
        let categories = game.categories ?? []
        let mechanics = game.mechanics ?? []
        return Group {
            if !categories.isEmpty || !mechanics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
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
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func bottomBar(_ game: Game) -> some View {
        let count = game.collections.filter { !$0.isDefault }.count
        return Button { showAddToCollection = true } label: {
            Text(count > 0 ? "Add to...  \(count)" : "Add to...")
                .font(.body.weight(.semibold))
                .frame(maxWidth: 200)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func playersStr(_ game: Game) -> String {
        if let min = game.minPlayers, let max = game.maxPlayers {
            return min == max ? "\(min)" : "\(min)–\(max)"
        }
        return "—"
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
                            .foregroundStyle(col.isDefault ? Color.secondary : Color.accentColor)
                        Text(col.name).foregroundStyle(col.isDefault ? Color.secondary : Color.primary)
                    }
                }
                .disabled(col.isDefault)
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

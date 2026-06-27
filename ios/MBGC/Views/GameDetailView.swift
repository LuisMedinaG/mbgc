import SwiftData
import SwiftUI

struct GameDetailView: View {
    let gameId: Int
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GameDetailViewModel()
    @State private var showAddToCollection = false

    private let langDep = ["", "No language", "Some text", "Moderate", "Extensive", "Unplayable"]

    var body: some View {
        Group {
            if let game = viewModel.game {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroImage(game)
                        statsRow(game)
                        descriptionSection(game)
                        tagsSection(game)
                        collectionsSection(game)
                        linksSection(game)
                    }
                    .padding()
                }
            } else if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.game?.name ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { viewModel.load(gameId: gameId, modelContext: modelContext) }
        .safeAreaInset(edge: .bottom) {
            if viewModel.game != nil { addToBar }
        }
        .sheet(isPresented: $showAddToCollection) {
            if let game = viewModel.game {
                AddToCollectionSheet(game: game)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var addToBar: some View {
        Button { showAddToCollection = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add to…")
                if let count = viewModel.game?.collections.count, count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(Color.accentColor, in: Capsule())
        }
        .padding(.bottom, 8)
    }

    private func heroImage(_ game: Game) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: game.image ?? game.thumbnail ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.title2).fontWeight(.bold).foregroundStyle(.white)
                HStack(spacing: 8) {
                    if let year = game.yearPublished, year > 0 {
                        Text(String(year)).font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                    if let rating = game.rating, rating > 0 {
                        Text("★ \(String(format: "%.1f", rating))").font(.caption).fontWeight(.bold).foregroundStyle(.white)
                    }
                    if let weight = game.weight, weight > 0 {
                        Text(String(format: "%.1f", weight)).font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                    if let dep = game.languageDependence, langDep.indices.contains(dep) {
                        Text(langDep[dep]).font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding()
        }
    }

    private func statsRow(_ game: Game) -> some View {
        GroupBox {
            HStack {
                VStack {
                    Text(playersStr(game)).font(.title3).fontWeight(.bold)
                    Text("Players").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider()
                VStack {
                    Text("\(game.playtime ?? 0)").font(.title3).fontWeight(.bold)
                    Text("Minutes").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider()
                VStack {
                    Text(game.weight.map { String(format: "%.1f", $0) } ?? "—").font(.title3).fontWeight(.bold)
                    Text("Complexity").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func descriptionSection(_ game: Game) -> some View {
        Group {
            if let desc = game.gameDescription, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About").font(.headline)
                    Text(desc).font(.subheadline)
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
                            ForEach(categories, id: \.self) { tag in
                                tagChip(tag, color: .blue)
                            }
                        }
                    }
                    if !mechanics.isEmpty {
                        Text("Mechanics").font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(mechanics, id: \.self) { tag in
                                tagChip(tag, color: .green)
                            }
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

    private func collectionsSection(_ game: Game) -> some View {
        GroupBox("Collections") {
            VStack(alignment: .leading, spacing: 8) {
                if game.collections.isEmpty {
                    Text("Not in any collection")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(game.collections.map(\.name), id: \.self) { name in
                            tagChip(name, color: .purple)
                        }
                    }
                }
            }
        }
    }

    private func linksSection(_ game: Game) -> some View {
        GroupBox("Links") {
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
    }

    private func playersStr(_ game: Game) -> String {
        if let min = game.minPlayers, let max = game.maxPlayers {
            return min == max ? "\(min)" : "\(min)-\(max)"
        }
        return "—"
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

// MARK: — Add to Collection Sheet

struct AddToCollectionSheet: View {
    let game: Game

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var saveError: String?
    @State private var showNewCollection = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { col in
                    let isIn = col.isDefault || game.collections.contains { $0.persistentModelID == col.persistentModelID }
                    Button { toggle(col) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: col.isDefault ? "square.grid.2x2.fill" : "folder.fill")
                                .foregroundStyle(col.isDefault ? .blue : .purple)
                            Text(col.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: isIn ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(isIn ? Color.accentColor : .secondary)
                                .font(.title3)
                        }
                    }
                    .disabled(col.isDefault)
                }
                if collections.isEmpty {
                    Text("No collections yet").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showNewCollection = true } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .alert("New Collection", isPresented: $showNewCollection) {
                TextField("Name", text: $newName)
                Button("Create") { createCollection() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func toggle(_ col: Collection) {
        guard !col.isDefault else { return }
        if let idx = col.games.firstIndex(where: { $0.bggId == game.bggId }) {
            col.games.remove(at: idx)
        } else {
            LocalLibrary.add([game], to: col)
        }
        save("Couldn't update collection.")
    }

    private func createCollection() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Collection(name: trimmed))
        save("Couldn't create collection.")
    }

    private func save(_ message: String) {
        do { try modelContext.save() } catch { saveError = message }
    }
}

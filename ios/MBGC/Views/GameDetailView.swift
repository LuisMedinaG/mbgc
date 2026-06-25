import SwiftUI
import SwiftData

struct GameDetailView: View {
    let gameId: Int
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GameDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    private let langDep = ["", "No language", "Some text", "Moderate", "Extensive", "Unplayable"]

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let game = viewModel.game {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroImage(game)
                        statsRow(game)
                        descriptionSection(game)
                        tagsSection(game)
                        vibesSection(game)
                        linksSection(game)
                        deleteSection(game)
                    }
                    .padding()
                }
            } else if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Game not found")
            }
        }
        .navigationTitle(viewModel.game?.name ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(gameId: gameId) }
    }

    private func heroImage(_ game: GameDetailDTO) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: game.image ?? game.thumbnail ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    if let year = game.yearPublished, year > 0 {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if game.rating > 0 {
                        Text("★ \(String(format: "%.1f", game.rating))")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    if game.weight > 0 {
                        Text(String(format: "%.1f", game.weight))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if game.languageDependence > 0 {
                        Text(langDep[game.languageDependence])
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding()
        }
    }

    private func statsRow(_ game: GameDetailDTO) -> some View {
        HStack {
            VStack {
                Text(playersStr(game))
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Players")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack {
                Text("\(game.playtime ?? 0)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Minutes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack {
                Text(game.weight > 0 ? String(format: "%.1f", game.weight) : "—")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Complexity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func descriptionSection(_ game: GameDetailDTO) -> some View {
        Group {
            if !game.description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                    Text(game.description)
                        .font(.subheadline)
                }
            }
        }
    }

    private func tagsSection(_ game: GameDetailDTO) -> some View {
        Group {
            if !game.categories.isEmpty || !game.mechanics.isEmpty || !game.types.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !game.categories.isEmpty {
                        Text("Categories")
                            .font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(game.categories, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    if !game.mechanics.isEmpty {
                        Text("Mechanics")
                            .font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(game.mechanics, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private func vibesSection(_ game: GameDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vibes")
                    .font(.headline)
                Spacer()
                if !viewModel.editingVibes {
                    Button("Edit") {
                        viewModel.startEditingVibes()
                    }
                    .font(.subheadline)
                }
            }

            if viewModel.editingVibes {
                ForEach(viewModel.collections) { col in
                    Button {
                        viewModel.toggleVibe(col.id)
                    } label: {
                        HStack {
                            Image(systemName: viewModel.selectedVibeIds.contains(col.id) ? "checkmark.square.fill" : "square")
                            Text(col.name)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                if viewModel.collections.isEmpty {
                    Text("No vibes yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Save") {
                        Task { await viewModel.saveVibes(gameId: game.id, modelContext: modelContext) }
                    }
                    .disabled(viewModel.isSaving)
                    Button("Cancel") {
                        viewModel.editingVibes = false
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                if game.vibes.isEmpty {
                    Text("No vibes assigned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(game.vibes.map(\.name), id: \.self) { vibe in
                            Text(vibe)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func linksSection(_ game: GameDetailDTO) -> some View {
        VStack(spacing: 8) {
            if let rulesUrl = game.rulesUrl, !rulesUrl.isEmpty {
                Link(destination: URL(string: rulesUrl)!) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Rules")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
            if let bggId = game.bggId {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func deleteSection(_ game: GameDetailDTO) -> some View {
        VStack {
            if viewModel.showDeleteConfirm {
                HStack {
                    Text("Delete \"\(game.name)\"?")
                    Button("Yes") {
                        Task {
                            if await viewModel.deleteGame(gameId: game.id, modelContext: modelContext) {
                                dismiss()
                            }
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(viewModel.isDeleting)
                    Button("Cancel") {
                        viewModel.showDeleteConfirm = false
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Button("Delete game", role: .destructive) {
                    viewModel.showDeleteConfirm = true
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func playersStr(_ game: GameDetailDTO) -> String {
        if let min = game.minPlayers, let max = game.maxPlayers {
            return min == max ? "\(min)" : "\(min)-\(max)"
        }
        return "—"
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > width, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            self.size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

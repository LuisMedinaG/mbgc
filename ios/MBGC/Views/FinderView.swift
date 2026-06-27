import SwiftData
import SwiftUI

// MARK: - Container

struct FinderView: View {
    @State private var flow = FinderFlow()
    @State private var hapticTrigger = 0
    @Query private var allGames: [Game]
    @Query(sort: \Collection.createdAt) private var collections: [Collection]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if !flow.hasCollections {
                    FinderEmptyView()
                } else if flow.isDone {
                    FinderResultView(flow: flow) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { flow.reset() }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if let axis = flow.currentAxis {
                    FinderStepView(
                        axis: axis,
                        options: flow.currentOptions,
                        survivorCount: flow.survivors.count,
                        step: flow.stepIndex,
                        total: flow.funnel.count,
                        onSelect: { option in
                            hapticTrigger += 1
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                flow.select(option)
                            }
                        },
                        onBack: flow.stepIndex > 0 ? {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                flow.back()
                            }
                        } : nil
                    )
                    .id(flow.stepIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: flow.stepIndex)
            .animation(.spring(response: 0.4),  value: flow.isDone)
            .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { bggId in
                GameDetailView(gameId: bggId)
            }
        }
        .onAppear { sync() }
        .onChange(of: allGames)    { sync() }
        .onChange(of: collections) { sync() }
    }

    private func sync() {
        flow.ownedGames = allGames
        flow.allCollections = collections
    }
}

// MARK: - Step

private struct FinderStepView: View {
    let axis: FinderAxis
    let options: [FinderOption]
    let survivorCount: Int
    let step: Int
    let total: Int
    let onSelect: (FinderOption) -> Void
    let onBack: (() -> Void)?

    // ponytail: thresholds match user spec — 2-col ≤4, 3-col 5-9, 4-col scrollable 10+
    private var cols: Int {
        switch options.count {
        case ...4:  return 2
        case 5...9: return 3
        default:    return 4
        }
    }
    private var isScrollable: Bool { options.count > 9 }
    private var rows: Int { (options.count + cols - 1) / cols }
    private let spacing: CGFloat = 10

    private var gridCols: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            questionBlock
            optionGrid
        }
        .padding(.bottom, 110)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard value.translation.width > 60,
                          abs(value.translation.height) < 100 else { return }
                    onBack?()
                }
        )
    }

    private var header: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text("Step \(step + 1) of \(total)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Skip") {
                onSelect(FinderOption(id: "skip", label: "Skip", count: survivorCount))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(axis.question)
                .font(.largeTitle.bold())
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(survivorCount) \(survivorCount == 1 ? "game" : "games") available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var optionGrid: some View {
        if isScrollable {
            ScrollView {
                LazyVGrid(columns: gridCols, spacing: spacing) {
                    ForEach(options) { opt in optionButton(opt).frame(height: 90) }
                }
                .padding(.horizontal, 16)
            }
            .contentMargins(.bottom, 16, for: .scrollContent)
        } else {
            // GeometryReader fills the remaining VStack height so buttons expand to fill the screen.
            GeometryReader { geo in
                let rowH = (geo.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
                LazyVGrid(columns: gridCols, spacing: spacing) {
                    ForEach(options) { opt in optionButton(opt).frame(height: max(rowH, 60)) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func optionButton(_ option: FinderOption) -> some View {
        let bg: Color = option.tint.flatMap { Color(hex: $0) } ?? Color(.secondarySystemBackground)
        let fgPrimary:   Color = option.solidBg ? .white : Color(.label)
        let fgSecondary: Color = option.solidBg ? .white.opacity(0.75) : .secondary

        return Button { onSelect(option) } label: {
            VStack(spacing: 6) {
                if let sym = option.symbol {
                    Image(systemName: sym)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(fgPrimary)
                }
                Text(option.label)
                    .font(.title2.bold())
                    .foregroundStyle(fgPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(option.count) \(option.count == 1 ? "game" : "games")")
                    .font(.subheadline)
                    .foregroundStyle(fgSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(FinderButtonStyle())
    }
}

// Slight press scale — same pattern as the rest of the app
private struct FinderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Result

struct FinderResultView: View {
    let flow: FinderFlow
    let onRestart: () -> Void

    @State private var showingAll = false

    private var top: [Game] { Array(flow.ranked.prefix(3)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tonight's Pick")
                        .font(.largeTitle.bold())
                    Text("\(flow.survivors.count) \(flow.survivors.count == 1 ? "game" : "games") matched")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if top.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "questionmark.circle",
                        description: Text("No games match those filters. Try different answers.")
                    )
                } else {
                    if let hero = top.first {
                        NavigationLink(value: hero.bggId) {
                            FinderHeroCard(game: hero)
                        }
                        .buttonStyle(.plain)
                    }

                    let runners = Array(top.dropFirst())
                    if !runners.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Also great")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                ForEach(runners) { game in
                                    NavigationLink(value: game.bggId) {
                                        FinderRunnerCard(game: game)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    if flow.survivors.count > 3 {
                        Button { showingAll = true } label: {
                            Text("See all \(flow.survivors.count) games")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(Color(.label))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onRestart) {
                        Text("Start over")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showingAll) {
            FinderAllMatchesView(games: flow.ranked)
        }
    }
}

// MARK: - Hero Card

private struct FinderHeroCard: View {
    let game: Game

    var body: some View {
        // Frame and clip on the ZStack (not children) so LinearGradient can't escape the 200pt box.
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: game.image ?? game.thumbnail ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.systemGray5)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(game.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                HStack(spacing: 14) {
                    if let r = game.rating, r > 0 {
                        Label(String(format: "%.1f", r), systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    if let lo = game.minPlayers, let hi = game.maxPlayers {
                        Label(lo == hi ? "\(lo)" : "\(lo)–\(hi)", systemImage: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let pt = game.playtime, pt > 0 {
                        Label("\(pt) min", systemImage: "clock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Runner Card

private struct FinderRunnerCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: game.thumbnail ?? game.image ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(game.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(Color(.label))

            if let r = game.rating, r > 0 {
                Label(String(format: "%.1f", r), systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - All Matches Sheet

private struct FinderAllMatchesView: View {
    let games: [Game]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(games) { game in
                NavigationLink(value: game.bggId) {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: game.thumbnail ?? "")) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(.systemGray5)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name).font(.body.weight(.semibold))
                            if let r = game.rating, r > 0 {
                                Label(String(format: "%.1f", r), systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("All Matches")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { bggId in
                GameDetailView(gameId: bggId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Empty State

private struct FinderEmptyView: View {
    var body: some View {
        ContentUnavailableView(
            "No Vibes Yet",
            systemImage: "square.stack.badge.plus",
            description: Text("Create collections in the Collection tab — add vibes like \"Party\" or \"Euro\" to get started.")
        )
    }
}

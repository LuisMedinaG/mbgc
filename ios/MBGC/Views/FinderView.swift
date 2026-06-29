import SwiftData
import SwiftUI

// MARK: - Container

struct FinderView: View {
    @Binding var path: [Int]
    @Binding var active: Bool   // false = intro cover (chrome visible); true = test running (chrome hidden)
    @State private var flow = FinderFlow()
    @State private var hapticTrigger = 0
    @State private var goingBack = false
    @Query private var allGames: [Game]
    @Query(sort: \Collection.createdAt) private var collections: [Collection]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if !flow.hasCollections {
                    FinderEmptyView()
                } else if !active {
                    FinderStartView { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { active = true } }
                } else if flow.isDone {
                    FinderResultView(flow: flow) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { exitTest() }
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
                                goingBack = false
                                flow.select(option)
                            }
                        },
                        // Back arrow always present: step >0 goes back a question, step 0 exits the test.
                        onBack: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                goingBack = true
                                if flow.stepIndex > 0 { flow.back() } else { exitTest() }
                            }
                        }
                    )
                    .id(flow.stepIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingBack ? .leading : .trailing).combined(with: .opacity),
                        removal:   .move(edge: goingBack ? .trailing : .leading).combined(with: .opacity)
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

    private func exitTest() {
        flow.reset()
        active = false
    }
}

// MARK: - Start Cover

private struct FinderStartView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.orange.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.5), radius: 24, y: 8)
                VStack(spacing: 8) {
                    Text("Tonight's Pick")
                        .font(.largeTitle.bold())
                    Text("Answer a few quick questions and we'll narrow your collection down to the perfect game.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
                Button(action: onStart) {
                    Text("Start")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
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
        // Note: a custom DragGesture was here for swipe-back, but it fought
        // the NavigationStack's built-in right-edge swipe and could double-back
        // or trigger while the user was scrolling the option grid. Removed —
        // use the explicit Back button or the NavigationStack edge swipe.
    }

    private var header: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Back")
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

    @State private var showAll = false
    @State private var bounce: CGFloat = 0
    @AppStorage("finderStartOverHintSeen") private var hintSeen = false

    private var top: [Game] { Array(flow.ranked.prefix(3)) }
    private var hasMore: Bool { flow.ranked.count > 3 }

    private var shareTopPick: String? {
        guard let game = top.first else { return nil }
        return "Tonight's pick: \(game.name)\nhttps://boardgamegeek.com/boardgame/\(game.bggId)"
    }

    var body: some View {
        ZStack {
            // Ambient background pulled from hero game art
            if let hero = top.first {
                CachedAsyncImage(url: URL(string: hero.image ?? hero.thumbnail ?? ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 80)
                    .opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // ponytail: overscroll hint, .refreshable still does the work.
                        GeometryReader { geo in
                            // Real pull (scroll minY) OR the one-time tutorial bounce reveals the hint.
                            let drive = max(geo.frame(in: .named("finderScroll")).minY, bounce)
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                Text("Start over…")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .opacity(min(max(drive / 60, 0), 1))
                            .offset(y: -40)
                        }
                        .frame(height: 0)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tonight's Pick")
                                .font(.largeTitle.bold())
                            Text("\(flow.survivors.count) \(flow.survivors.count == 1 ? "game" : "games") matched")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 24)
                        .id("topPick")

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

                            if showAll {
                                Button { toggleAll(proxy: proxy) } label: {
                                    HStack {
                                        Text("All \(flow.ranked.count) games")
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.up")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .id("allGames")
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(flow.ranked.enumerated()), id: \.element.bggId) { idx, game in
                                        NavigationLink(value: game.bggId) {
                                            HStack(spacing: 12) {
                                                Text("\(idx + 1)")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 24)
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
                                                Spacer()
                                            }
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 16)
                                            .foregroundStyle(.primary)
                                        }
                                        .buttonStyle(.plain)

                                        if idx < flow.ranked.count - 1 {
                                            Divider().padding(.leading, 96)
                                        }
                                    }
                                }
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }

                            if hasMore {
                                Button { toggleAll(proxy: proxy) } label: {
                                    Label(showAll ? "Show less" : "See all \(flow.ranked.count) recommendations",
                                          systemImage: showAll ? "chevron.up" : "list.number")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 72)
                    .offset(y: bounce)
                }
                .coordinateSpace(name: "finderScroll")
                .scrollIndicators(showAll ? .automatic : .hidden)
                .refreshable { onRestart() }   // native pull-down → start over (now works collapsed too)
                .overlay(alignment: .topTrailing) { menu }
                .task {
                    // One-time tutorial: dip down + reveal the "Start over…" hint, a few times.
                    guard !hintSeen, !top.isEmpty else { return }
                    try? await Task.sleep(for: .seconds(1.4))
                    for _ in 0..<3 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { bounce = 44 }
                        try? await Task.sleep(for: .seconds(0.45))
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { bounce = 0 }
                        try? await Task.sleep(for: .seconds(0.35))
                    }
                    hintSeen = true
                }
                // ponytail: toggle already animated via withAnimation in toggleAll; a
                // blanket .animation here rasterizes the whole expanding list into one
                // offscreen layer → "RBLayer: unable to create texture".
            }
        }
    }

    @ViewBuilder private var menu: some View {
        Menu {
            if let shareTopPick {
                ShareLink(item: shareTopPick) {
                    Label("Share Top Pick", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive, action: onRestart) {
                Label("Start over", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .tint(.primary)
        }
        .padding(.trailing, 16)
        .padding(.top, 4)
    }

    private func toggleAll(proxy: ScrollViewProxy) {
        let expanding = !showAll
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showAll = expanding }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo(expanding ? "allGames" : "topPick", anchor: .top) }
        }
    }
}

// MARK: - Hero Card

private struct FinderHeroCard: View {
    let game: Game

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: URL(string: game.image ?? game.thumbnail ?? ""))
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()

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
                            .foregroundStyle(.white.opacity(0.85))
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
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }
}

// MARK: - Runner Card

private struct FinderRunnerCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: URL(string: game.thumbnail ?? game.image ?? ""))
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(game.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(Color(.label))

            if let r = game.rating, r > 0 {
                Label(String(format: "%.1f", r), systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
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
                        CachedAsyncImage(url: URL(string: game.thumbnail ?? ""), size: 44, cornerRadius: 8)

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
            systemImage: "rectangle.stack.badge.plus",
            description: Text("Create collections in the Collection tab — add vibes like \"Party\" or \"Euro\" to get started.")
        )
    }
}

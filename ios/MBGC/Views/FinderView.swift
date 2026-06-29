import SwiftData
import SwiftUI

// MARK: - Container

/// Tonight tab. Holds the three-state machine: intro cover → quiz funnel → result.
/// `active` flips between intro and the running test so ContentView can hide the
/// floating nav during the quiz.
struct FinderView: View {
    @Binding var path: [Int]
    @Binding var active: Bool
    @State private var flow = FinderFlow()
    @State private var hapticTrigger = 0
    @State private var goingBack = false
    @Query private var allGames: [Game]
    @Query(sort: \Collection.createdAt) private var collections: [Collection]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Surface.background.ignoresSafeArea()

                if !flow.hasCollections {
                    FinderEmptyView()
                } else if !active {
                    FinderStartView { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { active = true } }
                } else if flow.isDone {
                    FinderResultView(flow: flow, onBack: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            goingBack = true
                            flow.back()
                        }
                    }, onRestart: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { exitTest() }
                    })
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
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Surface.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: Spacing.section)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Tonight")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Best Match")
                        .font(Typography.screenTitle)
                        .foregroundStyle(.primary)
                    Text("Answer a few quick questions and we'll recommend a game from your collection.")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screen)

                Spacer()

                VStack(spacing: Spacing.md) {
                    Button(action: onStart) {
                        Text("Start")
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.lg)
                            .background(Capsule().fill(BrandAccent.color))
                    }

                    Text("Three quick questions · about a minute")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, Spacing.section)
            }

            HStack {
                Spacer()
                ChromeButton(systemName: "gearshape") {
                    showSettings = true
                }
                .accessibilityLabel("Settings")
                .padding(.trailing, Spacing.screen)
                // Clear the Dynamic Island / status bar on every device.
                .padding(.top, 56)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
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

    var body: some View {
        VStack(spacing: 0) {
            header
            questionBlock
            optionList
        }
        .padding(.bottom, Spacing.floatingNavReserved)
        // Swipe right → back. Horizontal-only threshold keeps it from firing
        // while the user scrolls the option list vertically.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if v.translation.width > 80, abs(v.translation.height) < 80 { onBack?() }
                }
        )
    }

    private var header: some View {
        HStack {
            if let onBack {
                ChromeButton(systemName: "chevron.left", action: onBack)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text("Step \(step + 1) of \(total)")
                .font(Typography.step)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Skip") {
                onSelect(FinderOption(id: "skip", label: "Skip", count: survivorCount))
            }
            .font(Typography.bodyEmphasis)
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, Spacing.screen)
        // Clear the Dynamic Island / status bar on every device.
        .padding(.top, 56)
    }

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(axis.question)
                .font(Typography.screenTitle)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(survivorCount) \(survivorCount == 1 ? "game" : "games") available")
                .font(Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xxl)
    }

    private var optionList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(options) { option in
                    SelectableCard(
                        label: option.label,
                        count: option.count,
                        symbol: option.symbol,
                        isSelected: false,
                        onTap: { onSelect(option) }
                    )
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.bottom, Spacing.section)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Result

/// Final recommendation screen. Shows the top match as a hero card,
/// "Why this match" explanation, two compact alternatives, and the full ranking.
struct FinderResultView: View {
    let flow: FinderFlow
    let onBack: (() -> Void)?
    let onRestart: () -> Void

    @State private var showAll = false
    @State private var bounce: CGFloat = 0
    @AppStorage("finderStartOverHintSeen") private var hintSeen = false

    private var top: [Game] { Array(flow.ranked.prefix(3)) }
    private var alternatives: [Game] { Array(top.dropFirst()) }
    private var hasMore: Bool { flow.ranked.count > 3 }
    private var matchCountText: String {
        "\(flow.survivors.count) matching \(flow.survivors.count == 1 ? "game" : "games")"
    }

    /// Plain-language explanation of why the top match was chosen.
    private var explanation: String {
        var parts: [String] = []
        if let vibe = flow.chosenVibeLabel { parts.append("your \(vibe.lowercased()) playstyle") }
        if let players = flow.chosenPlayerLabel { parts.append("\(players.lowercased())") }
        if let duration = flow.chosenDurationLabel, duration != "Any" {
            parts.append("a \(duration.lowercased()) session")
        }
        guard !parts.isEmpty else {
            return "This game rose to the top from your collection using ratings, rank, and overall fit."
        }
        return "Matches your preferences for \(parts.joined(separator: ", "))."
    }

    /// Pills shown under the explanation. Order matters — most relevant signal first.
    private var explanationPills: [String] {
        var pills: [String] = []
        if let vibe = flow.chosenVibeLabel { pills.append(vibe) }
        if let players = flow.chosenPlayerLabel { pills.append(players) }
        if let duration = flow.chosenDurationLabel, duration != "Any" {
            pills.append(duration)
        }
        return pills
    }

    private var shareTopPick: String? {
        guard let game = top.first else { return nil }
        return "Best match: \(game.name)\nhttps://boardgamegeek.com/boardgame/\(game.bggId)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Surface.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        // ponytail: overscroll hint, .refreshable still does the work.
                        GeometryReader { geo in
                            let drive = max(geo.frame(in: .named("finderScroll")).minY, bounce)
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: "arrow.down")
                                Text("Start over…")
                            }
                            .font(Typography.metadata)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .opacity(min(max(drive / 60, 0), 1))
                            .offset(y: -40)
                        }
                        .frame(height: 0)

                        header
                            .id("topPick")

                        if top.isEmpty {
                            ContentUnavailableView(
                                "No Matches",
                                systemImage: "questionmark.circle",
                                description: Text("No games match those filters. Try different answers.")
                            )
                            .padding(.top, Spacing.section)
                        } else {
                            if let hero = top.first {
                                NavigationLink(value: hero.bggId) {
                                    HeroRecommendationCard(game: hero, matchPercent: flow.matchPercent(for: hero))
                                }
                                .buttonStyle(.plain)
                            }

                            if !explanationPills.isEmpty || !explanation.isEmpty {
                                WhyThisMatchCard(explanation: explanation, pills: explanationPills)
                            }

                            if !alternatives.isEmpty {
                                alternativesSection
                            }

                            fullRankingSection(scrollProxy: proxy)
                        }
                    }
                    .padding(.horizontal, Spacing.screen)
                    // The bottom navigation bar reserves ~120pt; the result scroll
                    // needs that much breathing room so the last row clears the nav.
                    .padding(.bottom, Spacing.floatingNavReserved)
                    .offset(y: bounce)
                }
                .coordinateSpace(name: "finderScroll")
                .scrollIndicators(showAll ? .automatic : .hidden)
                .refreshable { onRestart() }
                .overlay(alignment: .topLeading) { backButton }
                .overlay(alignment: .topTrailing) { shareButton }
                .task {
                    // One-time tutorial: dip down + reveal the "Start over…" hint a few times.
                    guard !hintSeen, !top.isEmpty else { return }
                    try? await Task.sleep(for: .seconds(5))
                    for _ in 0..<3 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { bounce = 44 }
                        try? await Task.sleep(for: .seconds(0.45))
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { bounce = 0 }
                        try? await Task.sleep(for: .seconds(3))
                    }
                    hintSeen = true
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if v.translation.width > 80, abs(v.translation.height) < 80 { onBack?() }
                }
        )
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tonight")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Best Match")
                .font(Typography.screenTitle)
                .foregroundStyle(.primary)
            Text(matchCountText)
                .font(Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.xxl)
    }

    // MARK: Alternatives

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionTitle(text: "Alternatives")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(alternatives) { game in
                        NavigationLink(value: game.bggId) {
                            AlternativeCard(game: game)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: Full ranking

    @ViewBuilder
    private func fullRankingSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionTitle(text: "Full Ranking")

            if showAll {
                Button { toggleAll(proxy: scrollProxy) } label: {
                    HStack {
                        Text("Show less")
                            .font(Typography.bodyEmphasis)
                            .foregroundStyle(BrandAccent.color)
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandAccent.color)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
                }
                .buttonStyle(.plain)
                .id("allGames")
                .padding(.bottom, Spacing.sm)

                VStack(spacing: 0) {
                    ForEach(Array(flow.ranked.enumerated()), id: \.element.bggId) { idx, game in
                        NavigationLink(value: game.bggId) {
                            FullRankingRow(
                                rank: idx + 1,
                                game: game,
                                matchPercent: flow.matchPercent(for: game)
                            )
                        }
                        .buttonStyle(.plain)

                        if idx < flow.ranked.count - 1 {
                            Rectangle()
                                .fill(Surface.separator)
                                .frame(height: 1)
                                .padding(.leading, 76)
                        }
                    }
                }
                .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
            }

            if hasMore && !showAll {
                Button { toggleAll(proxy: scrollProxy) } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "list.number")
                            .font(.system(size: 15, weight: .semibold))
                        Text("See all \(flow.ranked.count) recommendations")
                            .font(Typography.bodyEmphasis)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(BrandAccent.color))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var backButton: some View {
        if let onBack {
            ChromeButton(systemName: "chevron.left", action: onBack)
                .padding(.leading, Spacing.screen)
                // Clear the Dynamic Island / status bar on every device.
                .padding(.top, 56)
        }
    }

    @ViewBuilder private var shareButton: some View {
        if let shareTopPick {
            ShareLink(item: shareTopPick) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
            .accessibilityLabel("Share top pick")
            .padding(.trailing, Spacing.screen)
            .padding(.top, 56)
        } else {
            ChromeButton(systemName: "arrow.counterclockwise", action: onRestart)
                .padding(.trailing, Spacing.screen)
                .padding(.top, 56)
        }
    }

    private func toggleAll(proxy: ScrollViewProxy) {
        let expanding = !showAll
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showAll = expanding }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo(expanding ? "allGames" : "topPick", anchor: .top) }
        }
    }
}

// MARK: - Hero Recommendation Card

private struct HeroRecommendationCard: View {
    let game: Game
    let matchPercent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Cover image sits inside the card, never as a backdrop.
            GameCoverImage(
                url: URL(string: game.image ?? game.thumbnail ?? ""),
                size: nil,
                cornerRadius: Radius.large
            )
            .aspectRatio(4.0/3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(game.name)
                        .font(Typography.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    Text("\(matchPercent)% match")
                        .font(Typography.metadata)
                        .foregroundStyle(BrandAccent.color)
                }

                GameMetadataRow(
                    rating: game.rating,
                    minPlayers: game.minPlayers,
                    maxPlayers: game.maxPlayers,
                    playtime: game.playtime
                )
            }
        }
        .padding(Spacing.xl)
        .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
    }
}

// MARK: - Why This Match Card

private struct WhyThisMatchCard: View {
    let explanation: String
    let pills: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Why this match")
                .font(Typography.cardTitle)
                .foregroundStyle(.primary)

            Text(explanation)
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !pills.isEmpty {
                // Wrap onto multiple rows automatically via FlowLayout-free alternative:
                // a simple HStack + flow would need a custom layout; using a tight
                // horizontal scroll avoids that and stays calm visually.
                FlowPills(items: pills)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
    }
}

/// Wraps a list of pill strings onto multiple lines without horizontal scrolling.
/// Uses a Layout that wraps children onto rows when they exceed the available width.
private struct FlowPills: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: Spacing.sm, runSpacing: Spacing.sm) {
            ForEach(items, id: \.self) { item in
                TagPill(text: item)
            }
        }
    }
}

// MARK: - Alternative Card

private struct AlternativeCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GameCoverImage(
                url: URL(string: game.thumbnail ?? game.image ?? ""),
                size: nil,
                cornerRadius: Radius.medium
            )
            .aspectRatio(1.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            Text(game.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            GameMetadataRow(
                rating: game.rating,
                minPlayers: game.minPlayers,
                maxPlayers: game.maxPlayers,
                playtime: game.playtime
            )
        }
        .padding(Spacing.md)
        .frame(width: 160, alignment: .leading)
        .background(Surface.card, in: RoundedRectangle(cornerRadius: Radius.large))
    }
}

// MARK: - Full Ranking Row

private struct FullRankingRow: View {
    let rank: Int
    let game: Game
    let matchPercent: Int

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text("\(rank)")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            GameCoverImage(
                url: URL(string: game.thumbnail ?? game.image ?? ""),
                size: 48,
                cornerRadius: Radius.small
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(matchPercent)% match")
                    .font(Typography.caption)
                    .foregroundStyle(BrandAccent.color)
            }

            Spacer(minLength: Spacing.sm)

            GameMetadataRow(
                rating: game.rating,
                minPlayers: game.minPlayers,
                maxPlayers: game.maxPlayers,
                playtime: game.playtime
            )
            .frame(maxWidth: 160, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
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

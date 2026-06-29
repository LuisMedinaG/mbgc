import SwiftData
import SwiftUI

// MARK: - Container

struct FinderView: View {
    @Binding var path: [Int]
    @Binding var active: Bool   // false = intro cover (chrome visible); true = test running (chrome hidden)
    @Binding var isDone: Bool   // Bind to flow.isDone so ContentView can show/hide nav
    @State private var flow = FinderFlow()
    @State private var hapticTrigger = 0
    @State private var goingBack = false
    @Query private var allGames: [Game]
    @Query(sort: \Collection.createdAt) private var collections: [Collection]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

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
                    }) {
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
        .onChange(of: flow.isDone) { isDone = flow.isDone }
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
        ZStack {
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color.accentColor.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 24, y: 8)
                VStack(spacing: 12) {
                    Text("Best Match")
                        .font(DesignSystem.Typography.screenTitle)
                    Text("Answer a few quick questions and we'll narrow your collection down to the perfect game.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button(action: onStart) {
                    Text("Start")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            VStack {
                HStack {
                    Spacer()
                    HomeChromeButton(systemName: "gearshape", size: 44) {
                        showSettings = true
                    }
                    .accessibilityLabel("Settings")
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            .padding(.top, 8)
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
        .padding(.bottom, 140)
        // Swipe right → back, same gesture as FinderResultView. Horizontal-only
        // threshold (width>80, |height|<80) keeps it from firing while the user
        // scrolls the option grid vertically.
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
                .font(DesignSystem.Typography.stepLabel)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Skip") {
                onSelect(FinderOption(id: "skip", label: "Skip", count: survivorCount))
            }
            .font(DesignSystem.Typography.stepLabel)
            .foregroundStyle(Color.accentColor)
            .frame(width: 60, height: 44)
        }
        .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
        .padding(.top, DesignSystem.Spacing.s8)
    }

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s8) {
            Text(axis.question)
                .font(DesignSystem.Typography.screenTitle)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(survivorCount) \(survivorCount == 1 ? "game" : "games") available")
                .font(DesignSystem.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
        .padding(.top, DesignSystem.Spacing.sectionVerticalSpacing)
        .padding(.bottom, DesignSystem.Spacing.s24)
    }

    @ViewBuilder
    private var optionGrid: some View {
        if axis == .vibe {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.s16) {
                    ForEach(options) { opt in
                        vibeRow(opt)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
            }
        } else if axis == .players {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.s12) {
                    ForEach(options) { opt in
                        playerRow(opt)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
            }
        } else {
            if isScrollable {
                ScrollView {
                    LazyVGrid(columns: gridCols, spacing: spacing) {
                        ForEach(options) { opt in optionButton(opt).frame(height: 90) }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
                }
                .contentMargins(.bottom, 16, for: .scrollContent)
            } else {
                GeometryReader { geo in
                    let rowH = (geo.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
                    LazyVGrid(columns: gridCols, spacing: spacing) {
                        ForEach(options) { opt in optionButton(opt).frame(height: max(rowH, 60)) }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
            }
        }
    }

    private func vibeRow(_ option: FinderOption) -> some View {
        Button { onSelect(option) } label: {
            HStack(spacing: DesignSystem.Spacing.s16) {
                if let sym = option.symbol {
                    Image(systemName: sym)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.label)
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(Color(.label))
                    Text("\(option.count) \(option.count == 1 ? "game" : "games")")
                        .font(DesignSystem.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(DesignSystem.Spacing.s16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
            .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
        }
        .buttonStyle(FinderButtonStyle())
    }

    private func playerRow(_ option: FinderOption) -> some View {
        Button { onSelect(option) } label: {
            HStack {
                Text(option.label)
                    .font(DesignSystem.Typography.cardTitle)
                Spacer()
                Text("\(option.count) \(option.count == 1 ? "game" : "games")")
                    .font(DesignSystem.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.s20)
            .padding(.vertical, DesignSystem.Spacing.s16)
            .background(Color.accentColor.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.pill)
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 1)
            )
            .clipShape(Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(FinderButtonStyle())
    }

    private func optionButton(_ option: FinderOption) -> some View {
        let bg: Color = option.tint.flatMap { Color(hex: $0) } ?? Color(.secondarySystemGroupedBackground)
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
    let onBack: (() -> Void)?
    let onRestart: () -> Void

    @State private var showAll = false
    @State private var showRecommendationDetails = false
    @State private var bounce: CGFloat = 0
    @AppStorage("finderStartOverHintSeen") private var hintSeen = false

    private var top: [Game] { Array(flow.ranked.prefix(3)) }
    private var hasMore: Bool { flow.ranked.count > 3 }
    private var explanation: String {
        let selected = flow.picks
            .filter { $0.id != "skip" }
            .map(\.label)
        guard !selected.isEmpty else {
            return "This game rose to the top from your collection using ratings, rank, and overall fit."
        }
        return "Chosen because it fits \(selected.joined(separator: ", ")) and ranked highest across your ratings, BGG ratings, and overall fit."
    }

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

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s8) {
                            Text("Best Match")
                                .font(DesignSystem.Typography.screenTitle)
                            Text("\(flow.survivors.count) \(flow.survivors.count == 1 ? "game" : "games") matched")
                                .font(DesignSystem.Typography.metadata)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 30)
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
                                .padding(.top, -DesignSystem.Spacing.s8)

                                FinderWhyCard(explanation: explanation, picks: flow.picks)
                            }

                            let runners = Array(top.dropFirst())
                            if !runners.isEmpty {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.s12) {
                                    Text("Alternatives")
                                        .font(DesignSystem.Typography.sectionTitle)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: DesignSystem.Spacing.s12) {
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
                                        Text("Full Ranking (\(flow.ranked.count))")
                                            .font(DesignSystem.Typography.sectionTitle)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.up")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, DesignSystem.Spacing.s16)
                                    .padding(.vertical, DesignSystem.Spacing.s12)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
                                }
                                .buttonStyle(.plain)
                                .id("allGames")

                                LazyVStack(spacing: 0) {
                                    ForEach(Array(flow.ranked.enumerated()), id: \.element.bggId) { idx, game in
                                        NavigationLink(value: game.bggId) {
                                            HStack(spacing: DesignSystem.Spacing.s12) {
                                                Text("\(idx + 1)")
                                                    .font(DesignSystem.Typography.metadata.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 28)

                                                CachedAsyncImage(url: URL(string: game.thumbnail ?? ""), size: 48, cornerRadius: 8)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(game.name)
                                                        .font(DesignSystem.Typography.body.weight(.semibold))
                                                        .lineLimit(1)
                                                    FinderMetadataRow(game: game, style: .compact)
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, DesignSystem.Spacing.s8)
                                            .padding(.horizontal, DesignSystem.Spacing.s16)
                                            .foregroundStyle(.primary)
                                        }
                                        .buttonStyle(.plain)

                                        if idx < flow.ranked.count - 1 {
                                            Divider().padding(.leading, 88)
                                        }
                                    }
                                }
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
                            }

                            if hasMore {
                                Button { toggleAll(proxy: proxy) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: showAll ? "chevron.up" : "list.number")
                                            .font(.subheadline.weight(.semibold))
                                        Text(showAll ? "Show less" : "See all \(flow.ranked.count) recommendations")
                                            .font(.headline)
                                        Spacer()
                                        if !showAll {
                                            Image(systemName: "chevron.right")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.screenHorizontalMargin)
                    .padding(.bottom, 140)
                    .offset(y: bounce)
                }
                .coordinateSpace(name: "finderScroll")
                .scrollIndicators(showAll ? .automatic : .hidden)
                .refreshable { onRestart() }   // native pull-down → start over (now works collapsed too)
                .overlay(alignment: .topLeading) { backButton }
                .overlay(alignment: .topTrailing) { menu }
                .task {
                    // One-time tutorial: dip down + reveal the "Start over…" hint, a few times.
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
                // ponytail: toggle already animated via withAnimation in toggleAll; a
                // blanket .animation here rasterizes the whole expanding list into one
                // offscreen layer → "RBLayer: unable to create texture".
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if v.translation.width > 80, abs(v.translation.height) < 80 { onBack?() }
                }
        )
        .sheet(isPresented: $showRecommendationDetails) {
            FinderRecommendationDetailsView(text: explanation)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private var backButton: some View {
        if let onBack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Back")
            .padding(.leading, 16)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var menu: some View {
        Menu {
            Button {
                showRecommendationDetails = true
            } label: {
                Label("Recommendation Details", systemImage: "sparkles")
            }
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

// MARK: - Card Layout Tokens

/// Shared spacing so hero and runner cards stay consistent.
/// `imageGap` = artwork → title block. `titleGap` = title → metadata row.
private enum FinderCardLayout {
    static let heroImageGap: CGFloat = 14
    static let heroTitleGap: CGFloat = 8

    static let runnerImageGap: CGFloat = 10
    static let runnerTitleGap: CGFloat = 4
}

// MARK: - Hero Card

private struct FinderHeroCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s16) {
            CachedAsyncImage(url: URL(string: game.image ?? game.thumbnail ?? ""))
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
                .padding(.horizontal, DesignSystem.Spacing.s16)
                .padding(.top, DesignSystem.Spacing.s16)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s8) {
                Text(game.name)
                    .font(DesignSystem.Typography.cardTitle.bold())
                    .foregroundStyle(.primary)

                FinderMetadataRow(game: game, style: .prominent)
            }
            .padding(.horizontal, DesignSystem.Spacing.s16)
            .padding(.bottom, DesignSystem.Spacing.s20)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

private struct FinderWhyCard: View {
    let explanation: String
    let picks: [FinderOption]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s12) {
            Text("Why this match")
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s16) {
                Text(explanation)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.Spacing.s8) {
                        ForEach(picks.filter { $0.id != "skip" }) { pick in
                            Text(pick.label)
                                .font(DesignSystem.Typography.metadata.weight(.medium))
                                .padding(.horizontal, DesignSystem.Spacing.s12)
                                .padding(.vertical, DesignSystem.Spacing.s6)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
            .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
        }
    }
}

// MARK: - Runner Card

private struct FinderRunnerCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s12) {
            CachedAsyncImage(url: URL(string: game.thumbnail ?? game.image ?? ""))
                .frame(width: 140, height: 140)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.s4) {
                Text(game.name)
                    .font(DesignSystem.Typography.metadata.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(Color(.label))
                    .frame(height: 36, alignment: .top)

                FinderMetadataRow(game: game, style: .compact)
            }
        }
        .padding(DesignSystem.Spacing.s12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
        .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
    }
}

private struct FinderRecommendationDetailsView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(text)
                        .foregroundStyle(.secondary)
                }

                Section("How scoring works") {
                    detailRow("Your rating", "Strongest signal when available", "star.fill", Color(.systemOrange))
                    detailRow("BGG rating", "Community quality signal", "chart.line.uptrend.xyaxis", Color(.systemBlue))
                    detailRow("Player fit", "Bonus when BGG recommends the selected player count", "person.2.fill", Color(.systemGreen))
                    detailRow("BGG rank", "Small tiebreaker for widely respected games", "number", Color(.systemPurple))
                    detailRow("Want to play", "Nudge for games marked want to play", "heart.fill", Color(.systemPink))
                }

                Section {
                    Text("The picker first filters your library by your answers, then sorts matching games by the weighted signals above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recommendation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
    }
}

private struct FinderMetadataRow: View {
    enum Style { case prominent, compact }

    let game: Game
    let style: Style

    var body: some View {
        HStack(spacing: style == .prominent ? 12 : 8) {
            if let r = game.rating, r > 0 {
                metadataLabel(String(format: "%.1f", r), systemImage: "star.fill", color: Color.accentColor)
            }
            if let lo = game.minPlayers, let hi = game.maxPlayers {
                metadataLabel(lo == hi ? "\(lo)" : "\(lo)-\(hi)", systemImage: "person.2.fill", color: .secondary)
            }
            if let pt = game.playtime, pt > 0 {
                metadataLabel("\(pt)m", systemImage: "clock.fill", color: .secondary)
            }
        }
    }

    private func metadataLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(style == .prominent ? DesignSystem.Typography.metadata.weight(.medium) : .system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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

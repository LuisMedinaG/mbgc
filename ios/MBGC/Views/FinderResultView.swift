import SwiftUI

/// End-of-funnel screen: top pick (hero), two runners-up, collapsible full list,
/// share link. Pull-to-restart kicks the funnel back to step 0.
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
                        // Overscroll hint; .refreshable still does the work.
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
                                    FinderHeroCard(game: hero, matchPercent: flow.matchPercent(for: hero))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, -14)

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
                                                    Text("\(flow.matchPercent(for: game))% match")
                                                        .font(.caption)
                                                        .foregroundStyle(Color.accentColor)
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 72)
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
                // toggleAll owns the animation. A blanket .animation here rasterizes
                // the expanding list into one offscreen layer and can fail texture creation.
            }
        }
        .swipeBack { onBack?() }
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
    var matchPercent: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: FinderCardLayout.heroImageGap) {
            CachedAsyncImage(url: URL(string: game.image ?? game.thumbnail ?? ""))
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Color(.systemGray5))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: FinderCardLayout.heroTitleGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text(game.name)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    if let pct = matchPercent {
                        Text("\(pct)% match")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                FinderMetadataRow(game: game, style: .prominent)
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }
}

// MARK: - Runner Card

private struct FinderRunnerCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: FinderCardLayout.runnerImageGap) {
            CachedAsyncImage(url: URL(string: game.thumbnail ?? game.image ?? ""))
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: FinderCardLayout.runnerTitleGap) {
                Text(game.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(Color(.label))

                FinderMetadataRow(game: game, style: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }
}

// MARK: - Recommendation Details sheet

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

// MARK: - Metadata row (hero / runner variants)

private struct FinderMetadataRow: View {
    enum Style { case prominent, compact }

    let game: Game
    let style: Style

    var body: some View {
        HStack(spacing: style == .prominent ? 10 : 6) {
            if let r = game.rating, r > 0 {
                metadataLabel(String(format: "%.1f", r), systemImage: "star.fill", color: Color(.systemOrange))
            }
            if let lo = game.minPlayers, let hi = game.maxPlayers {
                metadataLabel(lo == hi ? "\(lo)" : "\(lo)-\(hi)", systemImage: "person.2.fill", color: Color(.systemBlue))
            }
            if let pt = game.playtime, pt > 0 {
                metadataLabel("\(pt)m", systemImage: "clock.fill", color: Color(.systemTeal))
            }
        }
    }

    private func metadataLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(style == .prominent ? .caption.weight(.semibold) : .caption2.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

import SwiftData
import SwiftUI

// MARK: - Container

struct FinderView: View {
    @State private var flow = FinderFlow()
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

    var body: some View {
        VStack(spacing: 0) {
            header
            questionBlock
            optionButtons
        }
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
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private var optionButtons: some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                Button { onSelect(option) } label: {
                    optionLabel(option)
                }
                .buttonStyle(FinderButtonStyle())
                .sensoryFeedback(.impact(weight: .medium), trigger: option.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity)
    }

    private func optionLabel(_ option: FinderOption) -> some View {
        VStack(spacing: 6) {
            Text(option.label)
                .font(.title2.bold())
                .foregroundStyle(Color(.label))
            Text("\(option.count) \(option.count == 1 ? "game" : "games")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// Gives each option button a slight press animation
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
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
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
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: game.image ?? game.thumbnail ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20))

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

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

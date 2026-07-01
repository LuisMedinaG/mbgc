import SwiftData
import SwiftUI

/// "Tonight's Pick" container. Hosts three modes (no collections, intro cover,
/// active test) and routes between them as the user advances through the funnel.
struct FinderView: View {
    @Binding var path: [Int]
    @Binding var active: Bool   // false = intro cover (chrome visible); true = test running (chrome hidden)
    @AppStorage("finderCarouselHintSeen") private var carouselHintSeen = false
    @State private var flow = FinderFlow()
    @State private var hapticTrigger = 0
    @State private var carouselHintOffset: CGFloat = 0
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
                } else {
                    finderCarousel
                }
            }
            .overlay(alignment: .topLeading) {
                if active {
                    // finder.FLOW.11
                    ChromeButton(systemName: "chevron.left", label: "Back") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { exitTest() }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 8)
                }
            }
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

    private var finderCarousel: some View {
        let questionIndices = flow.availableQuestionIndices
        let pageCount = questionIndices.count + 1

        return ZStack(alignment: .bottom) {
            TabView(selection: $flow.visiblePage) {
                ForEach(Array(questionIndices.enumerated()), id: \.element) { page, axisIndex in
                    FinderStepView(
                        axis: flow.funnel[axisIndex],
                        options: flow.options(at: axisIndex),
                        survivorCount: flow.survivors.count,
                        step: page,
                        total: questionIndices.count,
                        selectedOption: flow.picks[axisIndex],
                        onSelect: { option in
                            let isClearingSelection = flow.picks[axisIndex]?.id == option.id
                            hapticTrigger += 1
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                flow.select(at: axisIndex, option: option)
                                // finder.FLOW.10
                                if !isClearingSelection {
                                    flow.visiblePage = min(page + 1, flow.availableQuestionIndices.count)
                                }
                            }
                        }
                    )
                    .tag(page)
                }

                FinderResultView(flow: flow) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { exitTest() }
                }
                .tag(questionIndices.count)
            }
            .offset(x: carouselHintOffset)
            .tabViewStyle(.page(indexDisplayMode: .never))

            // finder.FLOW.7
            pageIndicator(pageCount: pageCount)
                .padding(.bottom, 0)
        }
        .task(id: active) {
            await playCarouselHintIfNeeded(questionCount: questionIndices.count)
        }
        .onChange(of: questionIndices) { _, indices in
            if flow.visiblePage > indices.count {
                flow.visiblePage = indices.count
            }
        }
    }

    private func sync() {
        flow.ownedGames = allGames
        flow.allCollections = collections
        flow.skipEmptySteps()
    }

    private func exitTest() {
        flow.reset()
        active = false
    }

    private func pageIndicator(pageCount: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == flow.visiblePage ? Color.primary : Color(.systemGray3))
                    .frame(width: index == flow.visiblePage ? 18 : 8, height: 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: flow.visiblePage)
        .accessibilityLabel("Page \(flow.visiblePage + 1) of \(pageCount)")
    }

    @MainActor
    private func playCarouselHintIfNeeded(questionCount: Int) async {
        guard active, !carouselHintSeen, questionCount > 1, flow.visiblePage == 0 else { return }
        try? await Task.sleep(for: .seconds(0.8))
        guard active, flow.visiblePage == 0 else { return }

        // finder.FLOW.7
        for _ in 0..<2 {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.65)) {
                carouselHintOffset = -32
            }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                carouselHintOffset = 0
            }
            try? await Task.sleep(for: .seconds(0.7))
        }
        carouselHintSeen = true
    }
}

// MARK: - Start cover

private struct FinderStartView: View {
    let onStart: () -> Void
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Surface.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.5), radius: 24, y: 8)
                VStack(spacing: 12) {
                    Text("Tonight's Pick")
                        .font(.largeTitle.bold())
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
                        .background(Color.orange)
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

// MARK: - Empty state

private struct FinderEmptyView: View {
    var body: some View {
        ContentUnavailableView(
            "No Vibes Yet",
            systemImage: "rectangle.stack.badge.plus",
            description: Text("Create collections in the Collection tab — add vibes like \"Party\" or \"Euro\" to get started.")
        )
    }
}

// MARK: - Shared button style

/// Slight press scale — same pattern as the rest of the app.
struct FinderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

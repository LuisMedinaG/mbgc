import SwiftData
import SwiftUI

/// "Tonight's Pick" container. Hosts three modes (no collections, intro cover,
/// active test) and routes between them as the user advances through the funnel.
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
                Color(hex: "F5F5F5").ignoresSafeArea()

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
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: goingBack ? .leading : .trailing)
                                .combined(with: .opacity),
                            removal:   .move(edge: goingBack ? .trailing : .leading)
                                .combined(with: .opacity)
                        )
                    )
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
        flow.skipEmptySteps()
    }

    private func exitTest() {
        flow.reset()
        active = false
    }
}

// MARK: - Start cover

private struct FinderStartView: View {
    let onStart: () -> Void
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color(hex: "F5F5F5").ignoresSafeArea()

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

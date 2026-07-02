import SwiftUI

/// First-launch intro: 2 welcome pages + a skippable BGG import page.
/// Gated by ContentView's `hasSeenOnboarding` @AppStorage flag.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    // Brand palette — no AccentColor asset exists, so hardcode here.
    private let cream = Color(hex: "#FBF6EC") ?? Color(.systemBackground)
    private let brandOrange = Color(hex: "#E8702A") ?? .orange

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [cream, cream, brandOrange.opacity(0.18)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                importPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        }
    }

    // MARK: Page 0 — Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            TileGridHero()
                .frame(height: 320)
                .clipped()
            Spacer()
            logo
            Text("Welcome to Overboard")
                .font(.system(size: 40, weight: .heavy))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            Text("Your board game collection\nat your fingertips.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Spacer()
            primaryButton("Get Started") { withAnimation { page = 1 } }
        }
        .padding(.bottom, 48)
    }

    // MARK: Page 1 — Feature tour

    private var featuresPage: some View {
        VStack(spacing: 0) {
            Spacer()
            logo
            Text("Welcome to Overboard")
                .font(.system(size: 36, weight: .heavy))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text("Your board game collection\nat your fingertips.")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(spacing: 22) {
                FeatureRow(symbol: "dice.fill", tint: brandOrange,
                           title: "Tonight", subtitle: "Answer a few questions, get tonight's pick.")
                FeatureRow(symbol: "magnifyingglass", tint: .green,
                           title: "Search", subtitle: "Look up any board game with ease.")
                FeatureRow(symbol: "square.stack.3d.up.fill", tint: .blue,
                           title: "Collect", subtitle: "Organize your collection into custom lists.")
                FeatureRow(symbol: "link", tint: .purple,
                           title: "Share", subtitle: "Send your lists to anyone, right from the app.")
            }
            .padding(.top, 32)
            .padding(.horizontal, 28)

            Spacer()
            primaryButton("Continue") { withAnimation { page = 2 } }
        }
        .padding(.bottom, 48)
    }

    // MARK: Page 2 — Import (skippable)

    private var importPage: some View {
        ImportView(dismissAll: onFinish, showCloseButton: false, autoAddToLibrary: true)
            .overlay(alignment: .topTrailing) {
                Button("Skip") { onFinish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }
    }

    // MARK: Shared pieces

    private var logo: some View {
        Image(systemName: "square.grid.2x2.fill")
            .font(.system(size: 56))
            .foregroundStyle(brandOrange)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Capsule().fill(brandOrange))
        }
        .padding(.horizontal, 28)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Decorative scattered tile grid evoking a box-art collage. No assets.
private struct TileGridHero: View {
    private let tints: [Color] = [
        Color(hex: "#DBEAFE") ?? .blue, Color(hex: "#FDE68A") ?? .yellow,
        Color(hex: "#FCA5A5") ?? .red, Color(hex: "#A7F3D0") ?? .green,
        Color(hex: "#C4B5FD") ?? .purple, Color(hex: "#FDBA74") ?? .orange,
    ]

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 5
            ZStack(alignment: .topLeading) {
                ForEach(0..<15, id: \.self) { i in
                    tile(i, cell: cell)
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(0.85)
    }

    private func tile(_ i: Int, cell: CGFloat) -> some View {
        let c = CGFloat(i % 5)
        let r = CGFloat(i / 5)
        let jitter = CGFloat((i * 37) % 24) - 12   // deterministic offset
        return RoundedRectangle(cornerRadius: 12)
            .fill(tints[i % tints.count])
            .frame(width: cell - 10, height: cell - 10)
            .offset(x: c * cell + 5, y: r * cell + jitter)
    }
}

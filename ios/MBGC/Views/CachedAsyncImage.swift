import SwiftUI

/// Square thumbnail backed by a dedicated URLSession + URLCache sized for board
/// game art (~50KB each), so images stay cached across scroll instead of being
/// re-fetched every time a cell recycles.
///
/// Avoids mutating the global `URLCache.shared` (which would affect every
/// URLSession in the app — including future telemetry / crash reporters).
///
/// Non-generic on purpose. Every call site wants the same square thumbnail.
/// Add a custom-content/placeholder init only when a screen needs one.
struct CachedAsyncImage: View {
    let url: URL?
    /// Square side length. When nil the image fills its parent — the caller is
    /// responsible for sizing and clipping (used by hero / full-bleed images).
    var size: CGFloat?
    var cornerRadius: CGFloat = 8
    var contentMode: ContentMode = .fill

    @State private var phase: Phase = .empty

    enum Phase {
        case empty, loading, success(Image), failure
    }

    var body: some View {
        Group {
            switch phase {
            case .success(let image):
                image.resizable()
                    .aspectRatio(contentMode: contentMode)
            case .empty, .loading, .failure:
                Color(.systemGray5)
            }
        }
        .modifier(SquareThumbnail(size: size, cornerRadius: cornerRadius))
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { phase = .failure; return }
        phase = .loading
        do {
            let (data, response) = try await ImageCache.shared.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let uiImage = UIImage(data: data) else {
                phase = .failure
                return
            }
            phase = .success(Image(uiImage: uiImage))
        } catch {
            phase = .failure
        }
    }
}

/// Applies a square frame + rounded clip when `size` is set; otherwise no-op so
/// the parent controls sizing (hero / full-bleed images).
private struct SquareThumbnail: ViewModifier {
    let size: CGFloat?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let size {
            content
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // Color.clear owns the layout size (whatever the parent proposes),
            // so the overlaid scaledToFill image can't propagate its intrinsic
            // size upward and inflate the surrounding layout wider than screen.
            Color.clear
                .overlay { content }
                .clipped()
        }
    }
}

/// Dedicated URLSession for board game thumbnails. Owns its own URLCache so we
/// don't mutate the global `URLCache.shared` (which would leak into every
/// URLSession in the app, including future telemetry).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    let session: URLSession

    private init() {
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }
}

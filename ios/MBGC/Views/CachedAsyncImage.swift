import SwiftUI

/// Drop-in replacement for `AsyncImage` that uses a dedicated URLSession with
/// a generous URLCache sized for board game thumbnails (~50KB each).
///
/// Replaces raw `AsyncImage` in collection rows so thumbnails stay cached
/// across scroll instead of being re-fetched every time a cell recycles.
///
/// Avoids mutating the global `URLCache.shared` (which would affect every
/// URLSession in the app — including future telemetry / crash reporters).
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var phase: Phase = .empty

    enum Phase {
        case empty, loading, success(Image), failure
    }

    var body: some View {
        Group {
            switch phase {
            case .empty, .loading:
                placeholder()
            case .success(let image):
                content(image)
            case .failure:
                placeholder()
            }
        }
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

extension CachedAsyncImage where Placeholder == Color {
    /// Convenience initializer for the most common case: square thumbnail
    /// with a gray placeholder and rounded corners. Use the main init when
    /// you need a custom placeholder (e.g. ProgressView or shimmer).
    init(url: URL?, size: CGFloat = 60, cornerRadius: CGFloat = 8) {
        self.init(
            url: url,
            content: { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            },
            placeholder: {
                Color(.systemGray5)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        )
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

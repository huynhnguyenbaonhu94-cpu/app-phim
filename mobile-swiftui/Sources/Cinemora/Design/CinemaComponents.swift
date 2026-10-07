import ImageIO
import SwiftUI
import UIKit

// MARK: - Screen header

struct CinemaHeader: View {
    let eyebrow: String
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                SectionEyebrow(text: eyebrow)
                Text(title)
                    .font(.auroraDisplay(30))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .shadow(color: Color.auroraViolet.opacity(0.35), radius: 18, y: 6)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(.auroraPress(scale: 0.92))
                .auroraCard(in: Circle(), tint: .auroraSky)
                .accessibilityLabel("Tìm phim")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Remote artwork

private final class PosterImageCache {
    static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "cinemora-posters")
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    /// Decodes and downsamples an image off the main thread.
    ///
    /// `UIImage(data:)` keeps the full-resolution bitmap around and defers
    /// decompression until the image is first drawn — that is, on the main
    /// thread while a grid is being rendered. ImageIO does both jobs up front on
    /// a background thread, and the resulting thumbnail is far smaller in memory.
    static func downsample(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
    }
}

struct PosterArt: View {
    let url: URL?
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    fallback
                    if isLoading {
                        AuroraShimmerOverlay()
                            .clipShape(Rectangle())
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .clipped()
            .task(id: url) {
                await loadImage(targetWidth: proxy.size.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadImage(targetWidth: CGFloat) async {
        guard let url else {
            image = nil
            isLoading = false
            return
        }

        // Decode at roughly the size the poster is drawn at, never at full
        // resolution: a 500x750 JPEG decoded at 3x costs ~13 MB per card and
        // blocked the main thread for every card of a grid.
        let width = targetWidth > 1 ? targetWidth : 300
        let neededPixels = min(max(width * displayScale, 240), 1400)

        if let cached = PosterImageCache.shared.object(forKey: url as NSURL),
           cached.size.width * cached.scale >= neededPixels * 0.9 {
            // `.task` re-runs whenever the view re-appears, so never write a
            // value that is already set: each write would invalidate this view
            // again immediately after a tab switch.
            if image !== cached { image = cached }
            if isLoading { isLoading = false }
            return
        }

        image = nil
        isLoading = true
        defer { isLoading = false }
        let retryDelays: [Duration] = [.milliseconds(250), .milliseconds(700), .seconds(1.5)]
        for attempt in 0..<retryDelays.count {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 20
                let (data, response) = try await PosterImageCache.session.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { continue }
                guard let decoded = await PosterImageCache.downsample(data, maxPixelSize: neededPixels) else { continue }
                guard !Task.isCancelled else { return }
                let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
                PosterImageCache.shared.setObject(decoded, forKey: url as NSURL, cost: cost)
                withAnimation(.easeOut(duration: 0.3)) { image = decoded }
                return
            } catch is CancellationError {
                return
            } catch {
                guard attempt < retryDelays.count - 1, !Task.isCancelled else { return }
                try? await Task.sleep(for: retryDelays[attempt])
            }
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.auroraRaised, Color.auroraInk, Color.auroraVoid],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.auroraViolet.opacity(0.3), Color.auroraViolet.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: 90
            )
            .frame(width: 180, height: 180)
            Image(systemName: "film")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.auroraViolet.opacity(0.8))
        }
    }
}

// MARK: - Poster card

struct MoviePosterCard: View {
    let movie: Movie
    var revealIndex: Int = 0

    var body: some View {
        NavigationLink(value: movie) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topLeading) {
                    PosterArt(url: movie.posterURL)
                    LinearGradient.auroraScrim
                    if let quality = movie.quality, !quality.isEmpty {
                        Text(quality.uppercased())
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Color.auroraVoid)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(LinearGradient.auroraPrimary))
                            .padding(9)
                    }
                    if let rating = movie.rating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").foregroundStyle(Color.auroraAmber)
                            Text(rating, format: .number.precision(.fractionLength(1)))
                                .foregroundStyle(.white)
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                    }
                }
                .aspectRatio(0.69, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                }
                // A single shadow per grid cell: a second, coloured shadow
                // doubled the offscreen blur work for every poster on screen.
                .shadow(color: Color.black.opacity(0.38), radius: 12, y: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(movie.name)
                        .font(.auroraLabel(13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text([movie.originName, movie.year.map { String($0) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.auroraPress(scale: 0.97))
        .auroraReveal(revealIndex)
    }
}

// MARK: - Horizontal shelf card

/// Wider 16:10 card used by the horizontal shelves on the home screen.
struct MovieShelfCard: View {
    let movie: Movie
    var width: CGFloat = 210

    var body: some View {
        NavigationLink(value: movie) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    PosterArt(url: movie.backdropURL)
                    LinearGradient.auroraScrim
                    VStack(alignment: .leading, spacing: 5) {
                        Text(movie.name)
                            .font(.auroraLabel(13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let year = movie.year {
                                Text(String(year))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            if let quality = movie.quality {
                                Text(quality.uppercased())
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.auroraVoid)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(LinearGradient.auroraPrimary))
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(width: width, height: width * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                }
                .shadow(color: Color.black.opacity(0.38), radius: 12, y: 8)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.auroraPress(scale: 0.97))
    }
}

// MARK: - Hero card

struct FeaturedMovieCard: View {
    let movie: Movie

    var body: some View {
        NavigationLink(value: movie) {
            ZStack(alignment: .bottomLeading) {
                PosterArt(url: movie.backdropURL)
                    .frame(height: 430)
                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.35), Color.black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .black))
                        Text("ĐỀ XUẤT HÔM NAY")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.8)
                    }
                    .foregroundStyle(Color.auroraVoid)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient.auroraPrimary))
                    .auroraHalo(.auroraViolet, radius: 18, opacity: 0.45)

                    Text(movie.name)
                        .font(.auroraDisplay(28))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

                    Text(movie.originName ?? "Một lựa chọn dành riêng cho bạn")
                        .font(.auroraBody(12))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let year = movie.year { metadataPill(String(year)) }
                        if let category = movie.categories?.first?.name { metadataPill(category) }
                        if let quality = movie.quality { metadataPill(quality) }
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Xem phim")
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(.auroraLabel(12, weight: .black))
                        .foregroundStyle(Color.auroraVoid)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(LinearGradient.auroraPrimary))
                        .auroraHalo(.auroraViolet, radius: 22, opacity: 0.5)

                        if let rating = movie.rating, rating > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundStyle(Color.auroraAmber)
                                Text(rating, format: .number.precision(.fractionLength(1)))
                            }
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                        }
                    }
                    .padding(.top, 3)
                }
                .padding(22)
            }
            .frame(height: 430)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(LinearGradient.auroraVeil, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.5), radius: 26, y: 14)
            .shadow(color: Color.auroraViolet.opacity(0.28), radius: 30, y: 12)
        }
        .buttonStyle(.auroraPress(scale: 0.985))
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
    }
}

// MARK: - Section heading

struct SectionHeading: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionEyebrow(text: eyebrow)
            Text(title)
                .font(.auroraDisplay(23))
                .tracking(-0.5)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty / error state

struct StateMessage: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var breathe = false

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(LinearGradient.auroraPrimary)
                    .opacity(0.24)
                    .frame(width: 68, height: 68)
                    .scaleEffect(breathe ? 1.08 : 0.94)
                    .blur(radius: 6)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.auroraViolet)
            }
            Text(title)
                .font(.auroraLabel(16, weight: .bold))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.auroraBody(12))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.auroraLabel(12, weight: .black))
                        .foregroundStyle(Color.auroraVoid)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(LinearGradient.auroraPrimary))
                }
                .buttonStyle(.auroraPress(scale: 0.95))
                .padding(.top, 3)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .auroraCard(cornerRadius: 26, tint: .auroraViolet, fill: 0.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - Reusable buttons

struct AuroraPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var loading: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .tint(Color.auroraVoid)
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .black))
                }
                Text(title).font(.auroraLabel(13, weight: .black))
            }
            .foregroundStyle(Color.auroraVoid)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(LinearGradient.auroraPrimary))
            .auroraHalo(.auroraViolet, radius: 20, opacity: enabled ? 0.42 : 0)
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.auroraPress(scale: 0.97))
        .disabled(!enabled || loading)
    }
}

struct AuroraGhostButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .auroraViolet
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .bold))
                }
                Text(title).font(.auroraLabel(12, weight: .bold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 0.9)
            }
        }
        .buttonStyle(.auroraPress(scale: 0.97))
    }
}

struct AuroraBackButton: View {
    var title: String = "Trở lại"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
                .font(.auroraLabel(13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
        }
        .buttonStyle(.auroraPress(scale: 0.94))
        .auroraSmoke(in: Capsule(), strength: 0.3)
        .accessibilityLabel(title)
    }
}

// MARK: - Layout helpers

/// A shelf of horizontally scrolling cards with snapping and a peeking next
/// item, used for the primary home sections.
struct MovieShelf: View {
    let movies: [Movie]
    var cardWidth: CGFloat = 210

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(movies) { movie in
                    MovieShelfCard(movie: movie, width: cardWidth)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// Sticky parallax hero. The artwork drifts and gently grows while the user
/// pulls the page down, and stays perfectly still at rest.
struct HeroParallax: View {
    let movie: Movie
    var height: CGFloat = 430
    var coordinateSpace: String

    var body: some View {
        // `visualEffect` reads the scroll geometry in the render tree instead of
        // through a `GeometryReader`, so scrolling no longer forces a SwiftUI
        // layout pass of this card on every frame.
        // The card also needs a definite width: given only a height, the title's
        // ideal (single-line) width would widen the whole lazy stack. Resolving
        // it from the scroll container keeps `visualEffect`, so no extra layout
        // pass is needed on every scroll frame.
        FeaturedMovieCard(movie: movie)
            .containerRelativeFrame(.horizontal) { length, _ in max(length - 40, 0) }
            .frame(height: height)
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .named(coordinateSpace)).minY
                let pull = max(minY, 0)
                return content
                    .offset(y: -pull * 0.30)
                    .scaleEffect(1 + pull / 2400)
            }
    }
}

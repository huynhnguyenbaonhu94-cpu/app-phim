import Foundation
import SwiftUI
import UIKit

@MainActor
final class CinemaImageLoader: ObservableObject {
    static let cache = NSCache<NSURL, UIImage>()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = URLCache.shared
        return URLSession(configuration: configuration)
    }()
    private static let diskCacheURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("cinemora-posters", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    @Published private(set) var image: UIImage?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var task: Task<Void, Never>?
    private var loadedURL: URL?
    private var displayedURL: URL?

    func load(_ url: URL?) {
        guard loadedURL != url || displayedURL == nil else { return }
        task?.cancel()
        failed = false
        loadedURL = url
        guard let url else { image = nil; displayedURL = nil; loading = false; return }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached; displayedURL = url; loading = false; return
        }
        if let cached = Self.diskImage(for: url) {
            image = cached
            displayedURL = url
            Self.cache.setObject(cached, forKey: url as NSURL)
            loading = false
            // Keep the disk image visible while checking for a newer response.
        }
        loading = true
        task = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<4 {
                guard !Task.isCancelled else { return }
                do {
                    var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
                    request.setValue("image/avif,image/webp,image/jpeg,image/png,*/*", forHTTPHeaderField: "Accept")
                    let (data, response) = try await Self.session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let decoded = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                    Self.cache.setObject(decoded, forKey: url as NSURL)
                    Self.storeOnDisk(data, for: url)
                    guard !Task.isCancelled, loadedURL == url else { return }
                    image = decoded; displayedURL = url; loading = false; failed = false; return
                } catch {
                    if attempt < 3 { try? await Task.sleep(for: .milliseconds(300 * (1 << attempt))) }
                }
            }
            guard !Task.isCancelled, loadedURL == url else { return }
            loading = false; failed = image == nil
        }
    }

    func retry() { load(loadedURL) }

    private static func diskKey(for url: URL) -> String {
        Data(url.absoluteString.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    private static func diskImage(for url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: diskCacheURL.appendingPathComponent(diskKey(for: url))) else { return nil }
        return UIImage(data: data)
    }

    private static func storeOnDisk(_ data: Data, for url: URL) {
        try? data.write(to: diskCacheURL.appendingPathComponent(diskKey(for: url)), options: .atomic)
    }
}

struct CinemaRemoteImage: View {
    let url: URL?
    let contentMode: ContentMode
    @StateObject private var loader = CinemaImageLoader()

    init(url: URL?, contentMode: ContentMode = .fill) { self.url = url; self.contentMode = contentMode }

    var body: some View {
        ZStack {
            fallback
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()
            }
            else if loader.loading { ProgressView().tint(.cinemaAccent) }
            else if loader.failed {
                Button { loader.retry() } label: { Label("Thử lại ảnh", systemImage: "arrow.clockwise") }
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.75))
                    .buttonStyle(.plain)
            }
        }
        .task(id: url) { loader.load(url) }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.1), Color.cinemaInk], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "film").font(.system(size: 26, weight: .light)).foregroundStyle(Color.cinemaAccent.opacity(0.7))
        }
    }
}

struct CinemaHeader: View {
    let eyebrow: String
    let title: String
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) { SectionEyebrow(text: eyebrow); Text(title).font(.system(size: 31, weight: .black, design: .rounded)).tracking(-1.2).foregroundStyle(.white) }
            Spacer(minLength: 8)
            if let action { Button(action: action) { Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 46, height: 46).contentShape(Circle()) }.buttonStyle(.plain).cinemaGlass(in: Circle(), tint: .white.opacity(0.1)).accessibilityLabel("Tìm phim") }
        }.padding(.top, 10).padding(.bottom, 15)
    }
}

struct PosterArt: View {
    let url: URL?
    let contentMode: ContentMode

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    var body: some View {
        CinemaRemoteImage(url: url, contentMode: contentMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()
    }
}

struct MoviePosterCard: View {
    let movie: Movie
    var body: some View {
        NavigationLink(value: movie) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    PosterArt(url: movie.posterURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    LinearGradient(colors: [.clear, .black.opacity(0.2)], startPoint: .center, endPoint: .bottom)
                    if let quality = movie.quality, !quality.isEmpty { Text(quality.uppercased()).font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.8).foregroundStyle(Color.cinemaAccent).padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.7), in: Capsule()).padding(9) }
                    if let rating = movie.rating, rating > 0 { HStack(spacing: 3) { Image(systemName: "star.fill"); Text(rating, format: .number.precision(.fractionLength(1))) }.font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 5).background(.black.opacity(0.66), in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8) }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.69, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.13), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
                Text(movie.name).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                Text([movie.originName, movie.year.map { String($0) }].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.54)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct FeaturedMovieCard: View {
    let movie: Movie
    var body: some View {
        NavigationLink(value: movie) {
            ZStack(alignment: .bottomLeading) {
                PosterArt(url: movie.backdropURL).frame(height: 400)
                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.32), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    Label("ĐỀ XUẤT HÔM NAY", systemImage: "sparkles").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1.8).foregroundStyle(Color.cinemaAccent)
                    Text(movie.name).font(.system(size: 27, weight: .black, design: .rounded)).tracking(-0.7).foregroundStyle(.white).lineLimit(2)
                    Text(movie.originName ?? "Một lựa chọn dành riêng cho bạn").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                    HStack(spacing: 8) { Image(systemName: "play.fill"); Text("Xem phim"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }.font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(Color.cinemaInk).padding(.horizontal, 17).padding(.vertical, 12).background(Color.cinemaAccent, in: Capsule()).padding(.top, 4)
                }.padding(22)
            }.frame(height: 400).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.2), lineWidth: 0.8)).shadow(color: .cinemaLavender.opacity(0.15), radius: 24, y: 12)
        }.buttonStyle(.plain)
    }

    private func metadataPill(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.88)).padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.12), in: Capsule()) }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { SectionEyebrow(text: eyebrow); Text(title).font(.system(size: 23, weight: .black, design: .rounded)).tracking(-0.7).foregroundStyle(.white) }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10) }
}

struct StateMessage: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundStyle(Color.cinemaAccent).frame(width: 58, height: 58).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20)).cinemaGlass(in: RoundedRectangle(cornerRadius: 20)); Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white); if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }; if let actionTitle, let action { Button(action: action) { Text(actionTitle).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.cinemaInk).padding(.horizontal, 18).padding(.vertical, 10).background(Color.cinemaAccent, in: Capsule()) }.buttonStyle(.plain).padding(.top, 4) } }.padding(26).frame(maxWidth: .infinity).cinemaGlass(in: RoundedRectangle(cornerRadius: 25), tint: .white.opacity(0.04)) }
}

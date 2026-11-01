import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// Kiểm tra và mở tệp đã tải bằng các API công khai của iOS.
/// VLC iOS hỗ trợ callback URL `vlc-x-callbacks://.../stream?url=...`.
enum OfflinePlaybackSupport {
    enum VLCAvailability: Equatable {
        case available
        case notInstalled
        case unsupportedFile(String)

        var message: String {
            switch self {
            case .available:
                return "Đã phát hiện VLC. iOS sẽ chuyển tệp qua bảng chia sẻ để VLC nhận quyền mở tệp đúng cách."
            case .notInstalled:
                return "Chưa phát hiện VLC trên thiết bị. Hãy cài VLC rồi thử chia sẻ tệp từ mục Đã tải."
            case .unsupportedFile(let extensionName):
                if extensionName == "movpkg" {
                    return "Bản HLS dạng MOVPKG do iOS quản lý nên VLC không mở trực tiếp được. Cinemora không chuyển đổi tệp này."
                }
                return "Định dạng .\(extensionName) không thể gửi trực tiếp sang VLC từ bản tải này."
            }
        }
    }

    private static let supportedFileExtensions: Set<String> = ["ts", "mp4", "m4v", "mov", "mkv", "avi", "m3u8"]

    static func validatePlayableFile(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "movpkg" {
            var isDirectory: ObjCBool = false
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil), !children.isEmpty else { return false }
            return AVURLAsset(url: url).assetCache?.isPlayableOffline == true
        }
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return false }
        if url.pathExtension.lowercased() == "m3u8" {
            guard let playlist = try? String(contentsOf: url, encoding: .utf8),
                  playlist.hasPrefix("#EXTM3U"), playlist.contains("#EXT-X-ENDLIST") else { return false }
            let segmentNames = playlist.split(whereSeparator: \.isNewline).map(String.init)
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            guard !segmentNames.isEmpty else { return false }
            return segmentNames.allSatisfy { name in
                let segment = url.deletingLastPathComponent().appendingPathComponent(name)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: segment.path),
                      let size = attrs[.size] as? NSNumber else { return false }
                return size.intValue > 0
            }
        }
        return supportedFileExtensions.contains(url.pathExtension.lowercased())
    }

    static func vlcAvailability(for fileURL: URL) -> VLCAvailability {
        if fileURL.pathExtension.lowercased() == "movpkg" { return .unsupportedFile("movpkg") }
        guard validatePlayableFile(fileURL) else {
            let extensionName = fileURL.pathExtension.isEmpty ? "không xác định" : fileURL.pathExtension.lowercased()
            return .unsupportedFile(extensionName)
        }
        guard let callbackURL = vlcCallbackURL(for: fileURL) else { return .unsupportedFile(fileURL.pathExtension.lowercased()) }
        let legacyURL = legacyVLCURL(for: fileURL)
        if UIApplication.shared.canOpenURL(callbackURL) || (legacyURL.map { UIApplication.shared.canOpenURL($0) } == true) {
            return .available
        }
        return .notInstalled
    }

    /// Used only to detect whether VLC is installed. The actual file handoff is
    /// performed by OfflineFileActivityView so iOS can grant cross-app access.
    private static func vlcCallbackURL(for fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "vlc-x-callbacks"
        components.host = "x-callback-url"
        components.path = "/stream"
        components.queryItems = [URLQueryItem(name: "url", value: fileURL.absoluteString)]
        return components.url
    }

    private static func legacyVLCURL(for fileURL: URL) -> URL? {
        // Legacy scheme cũng phải mang tệp, không được mở `vlc://` rỗng.
        URL(string: "vlc://\(fileURL.absoluteString)")
    }
}

extension DownloadManager.Item {
    /// Metadata tối thiểu để mở cùng trình phát Cinemora mà không cần gọi API.
    func offlineMovie() -> Movie {
        Movie(
            apiID: nil,
            slug: movieSlug,
            name: movieName,
            originName: nil,
            // Poster URL chưa được cache cùng bản tải; để nil nhằm không phát sinh request mạng.
            poster: nil,
            backdrop: nil,
            year: nil,
            quality: quality,
            episodeCurrent: nil,
            episodeTotal: nil,
            time: nil,
            lang: nil,
            description: nil,
            rating: nil,
            categories: nil,
            countries: nil,
            actors: nil,
            actorProfiles: nil,
            directors: nil,
            views: nil,
            alternativeNames: nil,
            status: nil,
            tmdbId: nil,
            imdbId: nil,
            createdAt: nil,
            updatedAt: nil,
            servers: nil,
            allowPip: false,
            episodeGroups: nil
        )
    }

    func offlineEpisode(fileURL: URL, subtitleTracks: [MovieEpisodeSubtitleTrack] = []) -> MovieEpisode {
        MovieEpisode(
            name: episodeName,
            slug: episodeSlug,
            filename: fileName,
            embedUrl: nil,
            streamUrl: nil,
            directStreamUrl: nil,
            subtitleUrl: nil,
            subtitleLabel: nil,
            bilingualSubtitleUrl: nil,
            // DownloadManager has already verified each local file. Do not put
            // remote episode-level subtitle URLs on an offline episode.
            subtitleTracks: subtitleTracks.filter { $0.subtitleURL?.isFileURL == true },
            qualities: nil,
            localFileURL: fileURL
        )
    }
}

/// Present the iOS share/open-in sheet with the actual sandbox file URL. Passing
/// the private Documents path directly through a custom URL scheme is not a
/// reliable cross-app file transfer; this system controller grants compatible
/// apps the file through the supported share extension mechanism.
struct OfflineFileActivityView: UIViewControllerRepresentable {
    let fileURLs: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

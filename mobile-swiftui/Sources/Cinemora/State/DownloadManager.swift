import AVFoundation
import Foundation
import Network
import Observation
import UIKit

/// Quản lý phim tải về để xem khi không có mạng.
///
/// Tải HLS offline bằng AVAssetDownloadURLSession để AVFoundation quản lý
/// playlist, media segments và package có thể phát lại từ file URL.
/// Các manifest/segment tự ghép từ phiên bản cũ không được coi là package hợp lệ.
/// Chỉ đánh dấu hoàn tất sau khi package đã lưu và AVURLAsset xác nhận playable.
@MainActor
@Observable
final class DownloadManager {
    enum Phase: String, Codable {
        case waiting, downloading, paused, finished, failed, unsupported

        var title: String {
            switch self {
            case .waiting: "Đang chờ"
            case .downloading: "Đang tải"
            case .paused: "Đã dừng"
            case .finished: "Đã tải xong"
            case .failed: "Lỗi"
            case .unsupported: "Không hỗ trợ"
            }
        }
    }

    /// Metadata for a sidecar whose source is remote but whose retained bytes are
    /// always kept in Cinemora's Application Support container.
    struct CachedSubtitle: Codable, Equatable, Hashable {
        var id: String
        var language: String
        var sourceURL: String
        var cacheFilename: String?
    }

    private struct SubtitleCacheKey: Hashable {
        let itemID: String
        let recordID: String
    }

    struct Item: Identifiable, Codable, Equatable {
        var id: String
        var movieSlug: String
        var movieName: String
        var poster: String?
        /// Stable filename in app-owned Application Support; nil for legacy records until backfilled.
        var posterCacheFilename: String?
        /// Optional for legacy downloads. The source URL is retained for stable
        /// identity while cacheFilename points only inside Application Support.
        var subtitleTracks: [CachedSubtitle]?
        var serverName: String
        var episodeName: String
        var episodeSlug: String
        var quality: String?
        var sourceURL: String
        /// Original proxy URL and one direct-origin fallback for manual HLS sources.
        var primarySourceURL: String?
        var fallbackSourceURL: String?
        var fileName: String
        /// AVFoundation owns native HLS packages at the returned relative path.
        var nativeAssetPath: String?
        var phase: Phase
        var receivedBytes: Int64
        var totalBytes: Int64
        var doneSegments: Int
        var totalSegments: Int
        var message: String?
        var updatedAt: Date
        /// Tổng thời lượng phim (giây) lấy từ các thẻ #EXTINF của playlist.
        var durationSeconds: Double?
        /// Băng thông của biến thể đã chọn (bit/giây) lấy từ #EXT-X-STREAM-INF.
        var bandwidth: Int?
        /// Tốc độ ước tính của phiên hiện tại (byte/giây), suy ra từ tiến trình HLS.
        var speed: Double?
        /// Thời điểm bắt đầu tải phiên hiện tại.
        var startedAt: Date?
        /// AVAssetDownloadTask reports a fraction/time-range, not byte counts.
        /// This stays separate from receivedBytes so estimated bytes are never
        /// persisted or presented as exact filesystem/network measurements.
        var nativeProgress: Double?
        var estimateUnavailable: Bool?

        var progress: Double {
            if let nativeProgress, nativeProgress.isFinite { return min(1, max(0, nativeProgress)) }
            if totalSegments > 0 { return min(1, max(0, Double(doneSegments) / Double(totalSegments))) }
            if totalBytes > 0 { return min(1, max(0, Double(receivedBytes) / Double(totalBytes))) }
            return phase == .finished ? 1 : 0
        }
        var isRunning: Bool { phase == .downloading || phase == .waiting }

        /// Tổng dung lượng ước tính từ băng thông biến thể và thời lượng playlist.
        var estimatedTotalBytes: Int64 {
            if phase == .finished { return max(receivedBytes, 0) }
            if estimateUnavailable == true { return 0 }
            if let bandwidth, bandwidth > 0, let durationSeconds, durationSeconds > 0 {
                let estimate = Double(bandwidth) / 8 * durationSeconds
                if estimate.isFinite, estimate > 0, estimate < Double(Int64.max) {
                    return Int64(estimate)
                }
            }
            return max(totalBytes, 0)
        }

        /// Dung lượng suy ra từ bitrate/thời lượng HLS, luôn đánh dấu gần đúng.
        var sizeText: String {
            if phase == .finished { return auroraByteText(max(receivedBytes, 0)) }
            let total = estimatedTotalBytes
            if phase == .downloading, progress <= 0.001 {
                return total > 0 ? "Tổng ước tính ~\(auroraByteText(total)) · đang kết nối" : "Đang chờ nguồn video phản hồi…"
            }
            guard total > 0 else {
                return estimateUnavailable == true ? "Dung lượng nguồn chưa xác định" : "Đang tính dung lượng…"
            }
            let estimatedDone = Double(total) * progress
            let safeDone = estimatedDone.isFinite && estimatedDone > 0 && estimatedDone < Double(Int64.max)
                ? Int64(estimatedDone) : 0
            return "Ước tính đã tải ~\(auroraByteText(safeDone)) / ~\(auroraByteText(total))"
        }

        var percentText: String {
            if phase == .downloading, progress <= 0.001 { return "Đang kết nối" }
            return "\(Int((min(1, max(0, progress)) * 100).rounded()))%"
        }

        var speedText: String {
            guard let speed, speed.isFinite, speed > 0, speed < Double(Int64.max) else { return "" }
            return "≈ \(auroraByteText(Int64(speed)))/s"
        }

        /// ETA is inferred from HLS progress and the estimated stream size.
        var etaText: String {
            guard phase == .downloading else { return "" }
            if progress <= 0.001, let startedAt, Date().timeIntervalSince(startedAt) >= 30 {
                return "Chưa nhận được dữ liệu từ nguồn sau 30 giây"
            }
            let total = estimatedTotalBytes
            guard total > 0 else { return estimateUnavailable == true ? "Chưa ước tính được thời gian" : "Đang tính thời gian còn lại…" }
            guard let speed, speed.isFinite, speed > 0 else { return "Đang tính thời gian còn lại…" }
            let remaining = Double(total) * (1 - progress)
            guard remaining > 0 else { return "Sắp hoàn tất…" }
            let estimate = remaining / speed
            guard estimate.isFinite else { return "còn rất lâu" }
            guard estimate < Double(Int.max) else { return "còn rất lâu" }
            let seconds = Int(estimate)
            if seconds < 60 { return "Ước còn <1 phút" }
            if seconds < 3600 { return "Ước còn ~\(seconds / 60) phút" }
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "Ước còn ~\(hours) giờ \(minutes) phút"
        }

        /// Tệp có sẵn trong máy và đang chờ xoá hay không.
        var canStart: Bool { phase == .paused || phase == .failed || phase == .waiting }
    }

    private(set) var items: [Item] = []
    /// Thông báo cho màn cài đặt khi thư mục đổi hoặc quyền truy cập bị thu hồi.
    var folderMessage: String?
    /// Network state is used for queueing and status only; cellular downloads are allowed.
    private(set) var isWiFi = false
    private(set) var isConnected = false
    private(set) var isCellular = false
    /// Cảnh báo offline hoặc nhắc dữ liệu di động trên màn Đã tải.
    var networkNotice: String?
    private let pathMonitor = NWPathMonitor()
    private var lastSaveAt: Date = .distantPast
    private static let offlineMessage = "Đang chờ kết nối Wi-Fi hoặc dữ liệu di động. Tác vụ tải sẽ tiếp tục khi có mạng."
    private static let cellularMessage = "Đang dùng dữ liệu di động. Tải phim có thể tiêu tốn nhiều dung lượng data."
    private static let maxSubtitleTracks = 12
    private static let maxSubtitleBytes = 8 * 1024 * 1024

    private var tasks: [String: Task<Void, Never>] = [:]
    private var estimateTasks: [String: Task<Void, Never>] = [:]
    private var subtitleTasks: [SubtitleCacheKey: Task<Void, Never>] = [:]
    private var pendingSubtitleCacheKeys: [SubtitleCacheKey] = []
    private var pendingSubtitleCacheCursor = 0
    private var pendingSubtitleCacheKeySet: Set<SubtitleCacheKey> = []
    private var failedSubtitleCacheKeys: Set<SubtitleCacheKey> = []
    private var posterTasks: [String: Task<Void, Never>] = [:]
    private var pendingPosterCacheIDs: [String] = []
    private var pendingPosterCacheCursor = 0
    private var pendingPosterCacheIDSet: Set<String> = []
    private var failedPosterCacheIDs: Set<String> = []
    private let maxConcurrentPosterCaches = 2
    private let maxConcurrentSubtitleCaches = 2
    private(set) var posterCacheRevision = 0
    private var progressSamples: [String: (date: Date, fraction: Double)] = [:]
    /// Số tập tải song song tối đa.
    private let maxConcurrent = 2
    /// Thư mục mặc định nằm trong Documents để hiện được trong app Tệp.
    private let defaultRoot: URL
    /// Nơi lưu danh sách tải xuống (dữ liệu nội bộ, không phải phim).
    private let metadataRoot: URL
    private var customBookmark: Data?
    private var scopedRoot: URL?
    private var storeURL: URL { metadataRoot.appendingPathComponent("downloads.json") }
    private var posterCacheRoot: URL { metadataRoot.appendingPathComponent("posters", isDirectory: true) }
    private var subtitleCacheRoot: URL { metadataRoot.appendingPathComponent("subtitles", isDirectory: true) }
    private let session: URLSession
    private let nativeDownloads = NativeHLSDownloadSession()
    private static let bookmarkKey = "cinemora.downloadFolderBookmark"

    /// Thư mục đang dùng để chứa phim tải về.
    var root: URL { scopedRoot ?? defaultRoot }
    var isUsingDefaultFolder: Bool { scopedRoot == nil }
    var folderName: String { isUsingDefaultFolder ? "Downloads (Cinemora)" : root.lastPathComponent }
    var folderPath: String { root.path }

    /// Dung lượng còn trống của thiết bị (byte).
    var freeBytes: Int64 {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Dung lượng còn trống, hiển thị trong màn cài đặt.
    var freeSpaceText: String {
        let free = freeBytes
        guard free > 0 else { return "Không xác định" }
        return auroraByteText(free)
    }

    /// Dung lượng còn phải tải của mọi bản đang chờ hoặc đang tải dở.
    private var reservedBytes: Int64 {
        items.filter { $0.phase != .finished }
            .reduce(Int64(0)) { total, item in
                let estimated = max(item.estimatedTotalBytes, 0)
                let received = max(item.receivedBytes, 0)
                let remaining = estimated > received ? estimated - received : 0
                return total > Int64.max - remaining ? Int64.max : total + remaining
            }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        metadataRoot = support.appendingPathComponent("Cinemora", isDirectory: true)
        try? FileManager.default.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? support
        defaultRoot = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Cinemora/1.0 (iOS)"]
        session = URLSession(configuration: configuration)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            let cellular = path.usesInterfaceType(.cellular)
            let online = path.status == .satisfied
            Task { @MainActor in self?.applyNetwork(wifi: wifi, cellular: cellular, online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.cinemora.downloads.network"))
        customBookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey)
        resolveCustomFolder()
        // Bản cũ lưu trong Application Support — chuyển sang thư mục mặc định mới.
        moveFiles(into: defaultRoot, from: [metadataRoot.appendingPathComponent("Downloads", isDirectory: true)])
        load()
        nativeDownloads.onProgress = { [weak self] id, fraction in
            Task { @MainActor in
                self?.recordNativeProgress(id: id, fraction: fraction)
            }
        }
        nativeDownloads.onPackage = { [weak self] id, location in
            Task { @MainActor in await self?.acceptPackage(id: id, at: location) }
        }
        nativeDownloads.onFailure = { [weak self] id, error in
            Task { @MainActor in
                guard let self, self.item(id: id)?.phase == .downloading else { return }
                self.handleNativeDownloadFailure(id: id, error: error)
            }
        }
        nativeDownloads.cancelUntrackedTasks()
    }

    // MARK: - Thư mục

    /// Người dùng vừa chọn thư mục trong app Tệp.
    func chooseFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            folderMessage = "Không lưu được quyền truy cập vào thư mục này. Hãy chọn thư mục khác."
            return
        }
        let previous = root
        customBookmark = data
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        // Move while both old and newly selected security scopes are active.
        moveFiles(into: url, from: [previous])
        resolveCustomFolder()
        guard scopedRoot != nil else { return }
        folderMessage = "Đã chuyển thư mục tải xuống sang \u{201C}\(folderName)\u{201D}."
    }

    /// Quay về thư mục mặc định của app.
    func useDefaultFolder() {
        let previous = root
        // The selected-folder scope must remain active until package moves finish.
        moveFiles(into: defaultRoot, from: [previous])
        scopedRoot?.stopAccessingSecurityScopedResource()
        scopedRoot = nil
        customBookmark = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderMessage = "Đang dùng lại thư mục mặc định của Cinemora."
    }

    /// Mở thư mục hiện tại trong app Tệp.
    ///
    /// `UIApplication.open` **không** mở được URL trỏ tới một thư mục, nên phải
    /// dùng scheme riêng của app Tệp (`shareddocuments://`) kèm đường dẫn.
    func openCurrentFolder() {
        let path = root.path
        let isDefault = isUsingDefaultFolder
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "shareddocuments://" + encoded) else {
            folderMessage = "Không tạo được liên kết tới thư mục này."
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            Task { @MainActor in
                self?.folderMessage = isDefault
                    ? "App Tệp không mở trực tiếp được thư mục này. Hãy mở app Tệp → Trên iPhone của tôi → Cinemora → Downloads."
                    : "App Tệp không mở trực tiếp được thư mục này. Bạn vẫn xem và xoá tệp được bằng nút “Xem tệp đã tải”."
            }
        }
    }

    /// Huỷ các tác vụ đang chạy; người dùng có thể tải lại từ đầu sau đó.
    func pauseAll() {
        let ids = items.filter { $0.phase == .downloading || $0.phase == .waiting }.map(\.id)
        for id in ids {
            pause(id, pumpQueue: false, persist: false)
        }
        save(force: true)
        pumpPosterCacheQueue(); pumpSubtitleCacheQueue()
    }

    /// Xoá toàn bộ bản đã tải xong (không đụng tới bản đang tải dở).
    func removeFinished() {
        for item in items where item.phase == .finished {
            remove(item.id)
        }
    }

    private func resolveCustomFolder() {
        scopedRoot?.stopAccessingSecurityScopedResource()
        scopedRoot = nil
        guard let bookmark = customBookmark else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            // Quyền bị thu hồi (xoá app Tệp, đổi máy…) — quay về mặc định thay vì
            // để mọi bản tải xuống thất bại trong im lặng.
            customBookmark = nil
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            folderMessage = "Không còn quyền ghi vào thư mục đã chọn, Cinemora đã quay về thư mục mặc định."
            return
        }
        scopedRoot = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if stale, let refreshed = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) {
            customBookmark = refreshed
            UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
        }
    }

    /// Chuyển các tệp phim đã tải sang thư mục mới, bỏ qua tệp đã có ở đích.
    private func moveFiles(into destination: URL, from sources: [URL]) {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for source in sources where source.standardizedFileURL != destination.standardizedFileURL {
            guard let files = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let ext = file.pathExtension.lowercased()
                // AVFoundation owns the `.movpkg` location: never move it.
                let canMove = ["mp4", "mov", "m4v", "mkv", "avi", "m3u8", "ts"].contains(ext)
                guard canMove else { continue }
                let target = destination.appendingPathComponent(file.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try? FileManager.default.moveItem(at: file, to: target)
            }
        }
    }

    // MARK: - Truy vấn

    func item(movieSlug: String, episodeSlug: String) -> Item? {
        items.first { $0.movieSlug == movieSlug && $0.episodeSlug == episodeSlug }
    }

    func item(id: String) -> Item? { items.first { $0.id == id } }

    /// Tra mục tải xuống theo tên tệp trong thư mục.
    func item(fileName: String) -> Item? { items.first { $0.fileName == fileName } }

    /// Tệp đã tải xong của một tập, dùng để phát offline.
    func localURL(movieSlug: String, episodeSlug: String) -> URL? {
        guard let item = item(movieSlug: movieSlug, episodeSlug: episodeSlug),
              item.phase == .finished else { return nil }
        return localURL(for: item)
    }

    /// Tệp video thực tế của một mục đã tải. Không trả về manifest, segment rời,
    /// thư mục hoặc tệp rỗng để UI không báo phát thành công giả.
    func localURL(for item: Item) -> URL? {
        guard item.fileName.lowercased().hasSuffix(".movpkg") else { return nil }
        let managedAsset = Self.assetURL(from: item.nativeAssetPath)
        let legacyPackage = root.appendingPathComponent(item.fileName, isDirectory: true)
        let oldSupportPackage = metadataRoot.appendingPathComponent("Downloads", isDirectory: true).appendingPathComponent(item.fileName, isDirectory: true)
        for package in [managedAsset, Optional(legacyPackage), Optional(oldSupportPackage)].compactMap({ $0 }) {
            guard OfflinePlaybackSupport.validatePlayableFile(package) else { continue }
            return package
        }
        return nil
    }

    /// Finds a successfully exported MP4/MOV copy for VLC or the iOS share sheet.
    func vlcExportURL(for item: Item) -> URL? {
        for ext in ["mp4", "mov"] {
            let url = exportDestination(for: item, fileExtension: ext)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { continue }
            return url
        }
        return nil
    }

    func exportDestination(for item: Item, fileExtension: String) -> URL {
        let ext = fileExtension.lowercased() == "mov" ? "mov" : "mp4"
        let stem = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        return root.appendingPathComponent("\(stem)-VLC.\(ext)")
    }

    /// A verified app-owned poster file, if it has been cached.
    func posterURL(for item: Item) -> URL? {
        // Observation must track this revision so completed artwork appears even
        // when the cache file did not exist during the previous render.
        _ = posterCacheRevision
        guard let filename = posterCacheFilename(for: item) else { return nil }
        let url = posterCacheRoot.appendingPathComponent(filename)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0, size <= 5 * 1024 * 1024 else { return nil }
        return url
    }

    private func posterCacheFilename(for item: Item) -> String? {
        let stem = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        let fallback = "\(Self.safeComponent(stem)).poster"
        let filename = item.posterCacheFilename ?? fallback
        guard !filename.isEmpty, URL(fileURLWithPath: filename).lastPathComponent == filename else { return nil }
        return filename
    }

    private static func assetURL(from storedPath: String?) -> URL? {
        guard let storedPath, !storedPath.isEmpty else { return nil }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let url = storedPath.hasPrefix("/")
            ? URL(fileURLWithPath: storedPath, isDirectory: true)
            : home.appendingPathComponent(storedPath, isDirectory: true)
        return url.standardizedFileURL
    }

    private static func storedAssetPath(for location: URL) -> String? {
        guard location.isFileURL else { return nil }
        let path = location.standardizedFileURL.path
        let homePath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.path
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        if path.hasPrefix(homePrefix) { return String(path.dropFirst(homePrefix.count)) }
        return path
    }

    /// Local-only tracks for the shared player. A metadata record without a
    /// verified regular file is deliberately omitted, so offline UI never
    /// claims that a missing sidecar is available.
    func subtitleTracks(for item: Item) -> [MovieEpisodeSubtitleTrack] {
        let current = self.item(id: item.id) ?? item
        guard let records = current.subtitleTracks else { return [] }
        return records.prefix(Self.maxSubtitleTracks).compactMap { record in
            guard !record.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.sourceURL.isEmpty,
                  let filename = safeSubtitleFilename(record.cacheFilename),
                  let sourceURL = URL(string: record.sourceURL) else { return nil }
            let localURL = subtitleCacheRoot.appendingPathComponent(filename)
            guard Self.subtitleFileSize(localURL) != nil else { return nil }
            return MovieEpisodeSubtitleTrack(language: record.language, subtitleUrl: sourceURL.absoluteString, localFileURL: localURL)
        }
    }

    func subtitleCacheStatus(for item: Item) -> String? {
        guard let records = self.item(id: item.id)?.subtitleTracks, !records.isEmpty else { return nil }
        let available = subtitleTracks(for: item).count
        if available == records.count { return "Phụ đề rời đã lưu: \(available)" }
        let active = records.filter {
            let key = SubtitleCacheKey(itemID: item.id, recordID: $0.id)
            return subtitleTasks[key] != nil || pendingSubtitleCacheKeySet.contains(key)
        }.count
        if active > 0 {
            return hasForegroundDownloadWork
                ? "Sẽ lưu phụ đề rời sau khi tải phim: \(available)/\(records.count)"
                : "Đang lưu phụ đề rời: \(available)/\(records.count)"
        }
        if isConnected { return "Phụ đề rời đã lưu \(available)/\(records.count) · còn thiếu một số track" }
        return "Phụ đề rời đã lưu \(available)/\(records.count) · cần kết nối mạng để tải phần còn lại"
    }

    /// Retry only subtitle sidecars; this never restarts or delays the movie
    /// package download. It is safe to call when offline.
    func retrySubtitleCaches(for id: String) {
        guard isConnected, let item = item(id: id), item.phase == .finished, let records = item.subtitleTracks else { return }
        for record in records.prefix(Self.maxSubtitleTracks) {
            let key = SubtitleCacheKey(itemID: item.id, recordID: record.id)
            failedSubtitleCacheKeys.remove(key)
            let destination = subtitleDestination(for: item, record: record)
            if record.cacheFilename == destination.lastPathComponent, Self.subtitleFileSize(destination) != nil { continue }
            if subtitleTasks[key] == nil, pendingSubtitleCacheKeySet.insert(key).inserted {
                pendingSubtitleCacheKeys.append(key)
            }
        }
        pumpSubtitleCacheQueue()
    }

    /// Mô tả đúng cách downloader lưu HLS để hiển thị trên màn Đã tải.
    func offlineStorageText(for item: Item) -> String {
        return "Đã lưu trong Cinemora · có thể xuất bản tương thích VLC"
    }

    var finishedCount: Int { items.filter { $0.phase == .finished }.count }
    var activeCount: Int { items.filter(\.isRunning).count }
    var totalBytes: Int64 {
        items.filter { $0.phase == .finished }.reduce(Int64(0)) { total, item in
            let size = max(item.receivedBytes, 0)
            return total > Int64.max - size ? Int64.max : total + size
        }
    }
    var totalSizeText: String { auroraByteText(totalBytes) }

    // MARK: - Hàng đợi

    @discardableResult
    func enqueue(movie: Movie, serverName: String, episode: MovieEpisode, quality: String? = nil) -> Item? {
        let slug = episode.slug.isEmpty ? episode.name : episode.slug
        let id = "\(movie.slug)|\(serverName)|\(slug)"
        if let index = items.firstIndex(where: { $0.id == id }) {
            mergeSubtitleMetadata(id: id, tracks: episode.availableSubtitleTracks)
            if items[index].phase == .finished {
                if let existing = item(id: id) { cachePoster(for: existing) }
                retrySubtitleCaches(for: id)
            } else {
                if let primaryURL = episode.playbackURL?.absoluteString {
                    let directURL = episode.directStreamURL?.absoluteString
                    mutate(id) {
                        $0.primarySourceURL = primaryURL
                        $0.sourceURL = primaryURL
                        $0.fallbackSourceURL = directURL == primaryURL ? nil : directURL
                    }
                }
                start(id)
            }
            return items[index]
        }
        guard let url = episode.playbackURL else { return nil }
        let directURL = episode.directStreamURL?.absoluteString
        let safeName = Self.packageName(movie: movie.slug, episode: slug, source: serverName)
        let subtitleTracks = Self.cachedSubtitleMetadata(from: episode.availableSubtitleTracks)
        let item = Item(
            id: id,
            movieSlug: movie.slug,
            movieName: movie.name,
            poster: movie.poster,
            posterCacheFilename: nil,
            subtitleTracks: subtitleTracks.isEmpty ? nil : subtitleTracks,
            serverName: serverName,
            episodeName: episode.name,
            episodeSlug: slug,
            quality: quality,
            sourceURL: url.absoluteString,
            primarySourceURL: url.absoluteString,
            fallbackSourceURL: directURL == url.absoluteString ? nil : directURL,
            fileName: safeName,
            nativeAssetPath: nil,
            phase: .waiting,
            receivedBytes: 0,
            totalBytes: 0,
            doneSegments: 0,
            totalSegments: 0,
            message: nil,
            updatedAt: Date(),
            durationSeconds: nil,
            bandwidth: nil,
            speed: nil,
            startedAt: nil,
            nativeProgress: nil,
            estimateUnavailable: nil
        )
        items.insert(item, at: 0)
        save()
        start(id)
        return item
    }

    func start(_ id: String) {
        guard tasks[id] == nil, let item = item(id: id), item.phase != .finished else { return }
        guard isConnected else {
            mutate(id) { $0.phase = .waiting; $0.message = Self.offlineMessage }
            networkNotice = Self.offlineMessage; save(force: true); return
        }
        guard tasks.count < maxConcurrent else {
            mutate(id) { $0.phase = .waiting }; save(); return
        }
        guard let url = URL(string: item.sourceURL), url.scheme?.lowercased().hasPrefix("http") == true else {
            mutate(id) { $0.phase = .failed; $0.message = "Đường dẫn HLS không hợp lệ." }; save(force: true); return
        }
        let retryingOrigin = item.message?.localizedCaseInsensitiveContains("đang thử link video gốc") == true ? item.message : nil
        mutate(id) {
            $0.phase = .downloading; $0.message = retryingOrigin; $0.receivedBytes = 0; $0.totalBytes = 0
            $0.doneSegments = 0; $0.totalSegments = 0; $0.nativeProgress = 0; $0.speed = nil
            $0.durationSeconds = nil; $0.bandwidth = nil; $0.estimateUnavailable = nil; $0.startedAt = Date()
        }
        if isCellular { networkNotice = Self.cellularMessage }
        progressSamples[id] = (Date(), 0)
        guard nativeDownloads.start(id: id, url: url, title: "\(item.movieName) — \(item.episodeName)") else {
            progressSamples[id] = nil
            mutate(id) { $0.phase = .failed; $0.nativeProgress = nil; $0.message = "Không tạo được AVAssetDownloadTask cho nguồn HLS này." }
            save(force: true); return
        }
        tasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.refreshStalledStatus(id: id)
            }
        }
        beginSizeEstimation(id: id, url: url)
        save(force: true)
    }

    private func beginSizeEstimation(id: String, url: URL) {
        estimateTasks[id]?.cancel()
        let session = self.session
        estimateTasks[id] = Task { [weak self, session] in
            let estimate = await Self.playlistEstimate(for: url, session: session)
            guard !Task.isCancelled, let self, self.item(id: id)?.phase == .downloading else { return }
            self.estimateTasks[id] = nil
            self.mutate(id) { item in
                if let estimate {
                    item.durationSeconds = estimate.duration
                    item.bandwidth = estimate.bandwidth
                    item.estimateUnavailable = false
                } else {
                    item.durationSeconds = nil
                    item.bandwidth = nil
                    item.estimateUnavailable = true
                }
            }
            self.save(force: true)
        }
    }

    private func recordNativeProgress(id: String, fraction: Double) {
        guard let current = item(id: id), current.phase == .downloading else { return }
        let reported = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let normalized = max(current.nativeProgress ?? 0, reported)
        let now = Date()
        var measuredSpeed: Double?
        var clearStaleSpeed = false
        if let previous = progressSamples[id] {
            let elapsed = now.timeIntervalSince(previous.date)
            // Keep a stable sample window: updating the baseline on every KVO
            // tick (often <0.5s) made ETA speed impossible to calculate.
            if elapsed >= 1.0 {
                let estimatedBytes = current.estimatedTotalBytes
                if normalized > previous.fraction, estimatedBytes > 0 {
                    let rate = Double(estimatedBytes) * (normalized - previous.fraction) / elapsed
                    if rate.isFinite, rate > 0, rate < 1_000_000_000 { measuredSpeed = rate }
                } else if elapsed >= 6 {
                    clearStaleSpeed = true
                }
                progressSamples[id] = (now, normalized)
            }
        } else {
            progressSamples[id] = (now, normalized)
        }
        mutate(id) { item in
            item.nativeProgress = normalized
            if let measuredSpeed {
                item.speed = item.speed.map { $0 * 0.72 + measuredSpeed * 0.28 } ?? measuredSpeed
            } else if clearStaleSpeed {
                item.speed = nil
            }
        }
        save()
    }

    private func refreshStalledStatus(id: String) {
        guard let current = item(id: id), current.phase == .downloading else { return }
        let hasProgress = current.progress > 0.001
        let isStalled = !hasProgress && current.startedAt.map { Date().timeIntervalSince($0) >= 30 } == true
        let stalledMessage = "Chưa nhận được tiến trình từ nguồn video sau 30 giây. Có thể thử lại hoặc chọn nguồn khác."
        if isStalled,
           let fallback = current.fallbackSourceURL,
           fallback != current.sourceURL,
           URL(string: fallback)?.scheme?.lowercased().hasPrefix("http") == true {
            nativeDownloads.cancel(id: id)
            estimateTasks[id]?.cancel(); estimateTasks[id] = nil
            progressSamples[id] = nil
            tasks[id]?.cancel(); tasks[id] = nil
            mutate(id) {
                $0.sourceURL = fallback
                $0.fallbackSourceURL = nil
                $0.phase = .waiting
                $0.receivedBytes = 0; $0.totalBytes = 0; $0.nativeProgress = nil; $0.speed = nil
                $0.message = "Nguồn qua máy chủ Cinemora chưa phát sinh tiến trình sau 30 giây; đang thử link video gốc."
            }
            save(force: true)
            start(id)
            return
        }
        if isStalled, current.message != stalledMessage {
            mutate(id) { $0.message = stalledMessage }
            save()
        } else if hasProgress, current.message == stalledMessage {
            mutate(id) { $0.message = nil }
            save()
        }
    }

    private func handleNativeDownloadFailure(id: String, error: Error) {
        estimateTasks[id]?.cancel(); estimateTasks[id] = nil
        progressSamples[id] = nil
        tasks[id]?.cancel(); tasks[id] = nil
        guard let current = item(id: id) else { return }
        nativeDownloads.forget(id: id)

        // If connectivity disappeared, keep the row queued. A background
        // AVAssetDownload task may fail on a radio transition even though a
        // fresh task can start as soon as either radio is usable again.
        guard isConnected else {
            mutate(id) {
                $0.phase = .waiting
                $0.receivedBytes = 0; $0.totalBytes = 0; $0.nativeProgress = nil; $0.speed = nil
                $0.message = Self.offlineMessage
            }
            networkNotice = Self.offlineMessage
            save(force: true)
            return
        }

        if let fallback = current.fallbackSourceURL,
           fallback != current.sourceURL,
           URL(string: fallback)?.scheme?.lowercased().hasPrefix("http") == true {
            mutate(id) {
                $0.sourceURL = fallback
                $0.fallbackSourceURL = nil
                $0.phase = .waiting
                $0.receivedBytes = 0; $0.totalBytes = 0; $0.nativeProgress = nil; $0.speed = nil
                $0.message = "Nguồn qua máy chủ Cinemora không tải được; đang thử link video gốc."
            }
            save(force: true)
            start(id)
            return
        }

        mutate(id) {
            $0.phase = .failed
            $0.receivedBytes = 0; $0.totalBytes = 0; $0.nativeProgress = nil; $0.speed = nil
            $0.message = error.localizedDescription
        }
        save(force: true)
        pump()
    }

    nonisolated private static func playlistEstimate(for url: URL, session: URLSession) async -> (duration: Double, bandwidth: Int)? {
        do {
            let data = try await Self.fetch(url, session: session)
            let text = try Self.text(from: data)
            let resolved = try await Self.resolvePlaylist(text, base: url) { childURL in
                try await Self.fetch(childURL, session: session)
            }
            guard resolved.duration.isFinite, resolved.duration > 0, resolved.bandwidth > 0 else { return nil }
            return (resolved.duration, resolved.bandwidth)
        } catch {
            return nil
        }
    }

    /// Mở khoá hàng đợi: chạy tiếp các mục đang chờ khi có chỗ trống.
    private func pump() {
        for item in items where item.phase == .waiting {
            if tasks.count >= maxConcurrent { break }
            start(item.id)
        }
    }

    /// AVAssetDownloadTask has no reliable pause/resume lifecycle here; stopping cancels.
    func pause(_ id: String) {
        pause(id, pumpQueue: true, persist: true)
    }

    private func pause(_ id: String, pumpQueue: Bool, persist: Bool) {
        guard let item = item(id: id), item.phase == .downloading || item.phase == .waiting else { return }
        nativeDownloads.cancel(id: id)
        estimateTasks[id]?.cancel(); estimateTasks[id] = nil
        progressSamples[id] = nil
        tasks[id]?.cancel(); tasks[id] = nil
        mutate(id) { $0.phase = .paused; $0.receivedBytes = 0; $0.totalBytes = 0; $0.nativeProgress = nil; $0.speed = nil; $0.message = "Đã huỷ tải. Bấm Tải lại để bắt đầu lại từ đầu." }
        if persist { save(force: true) }
        if pumpQueue { pump(); pumpPosterCacheQueue(); pumpSubtitleCacheQueue() }
    }

    func retry(_ id: String) {
        guard let item = item(id: id) else { return }
        estimateTasks[id]?.cancel(); estimateTasks[id] = nil
        progressSamples[id] = nil
        let storedURL = Self.assetURL(from: item.nativeAssetPath)
        let legacyURL = root.appendingPathComponent(item.fileName, isDirectory: true)
        let oldSupportURL = metadataRoot.appendingPathComponent("Downloads", isDirectory: true).appendingPathComponent(item.fileName, isDirectory: true)
        for url in [storedURL, Optional(legacyURL), Optional(oldSupportURL), Optional(exportDestination(for: item, fileExtension: "mp4")), Optional(exportDestination(for: item, fileExtension: "mov"))].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
        }
        mutate(id) {
            if let original = $0.primarySourceURL, original != $0.sourceURL { $0.fallbackSourceURL = original }
            $0.fileName = Self.packageName(movie: $0.movieSlug, episode: $0.episodeSlug, source: $0.serverName)
            $0.nativeAssetPath = nil; $0.phase = .waiting; $0.receivedBytes = 0; $0.totalBytes = 0
            $0.nativeProgress = nil; $0.speed = nil; $0.message = nil
        }
        start(id)
    }

    /// Keep native HLS tasks alive across Wi-Fi/cellular transitions. URLSession
    /// is configured for both radios and waits for connectivity when offline.
    private func applyNetwork(wifi: Bool, cellular: Bool, online: Bool) {
        let wasConnected = isConnected
        isWiFi = wifi && online
        isCellular = cellular && online
        isConnected = online
        guard online else {
            networkNotice = Self.offlineMessage
            for item in items where item.phase == .waiting && item.message != Self.offlineMessage {
                mutate(item.id) { $0.message = Self.offlineMessage }
            }
            save()
            return
        }
        networkNotice = isCellular ? Self.cellularMessage : nil
        if !wasConnected {
            failedPosterCacheIDs.removeAll()
            failedSubtitleCacheKeys.removeAll()
        }
        for item in items where item.phase == .waiting && item.message == Self.offlineMessage {
            mutate(item.id) { $0.message = nil }
        }
        pump()
        // Backfill only completed packages. Auxiliary image/subtitle requests
        // must not compete with the two foreground HLS downloads.
        for item in items where item.phase == .finished {
            cachePoster(for: item)
            retrySubtitleCaches(for: item.id)
        }
    }

    /// Xoá một bản tải xuống: **xoá luôn tệp phim trong thư mục tải xuống**,
    /// người dùng không phải xoá thủ công lần nữa.
    ///
    /// Nếu tệp không xoá được (thường là do mất quyền truy cập thư mục đã chọn)
    /// thì mục được giữ lại kèm lời báo, thay vì biến mất khỏi danh sách trong khi
    /// tệp vẫn còn chiếm dung lượng máy.
    func remove(_ id: String) {
        guard let item = item(id: id) else { return }
        nativeDownloads.cancel(id: id)
        estimateTasks[id]?.cancel(); estimateTasks[id] = nil
        progressSamples[id] = nil
        tasks[id]?.cancel()
        tasks[id] = nil
        let file = root.appendingPathComponent(item.fileName, isDirectory: item.fileName.lowercased().hasSuffix(".movpkg"))
        do {
            let managedAsset = Self.assetURL(from: item.nativeAssetPath)
            let oldSupportAsset = metadataRoot.appendingPathComponent("Downloads", isDirectory: true).appendingPathComponent(item.fileName, isDirectory: true)
            let exports = [exportDestination(for: item, fileExtension: "mp4"), exportDestination(for: item, fileExtension: "mov")]
            var candidates = [file]
            if let managedAsset { candidates.append(managedAsset) }
            candidates.append(oldSupportAsset)
            candidates.append(contentsOf: exports)
            var seen: Set<String> = []
            for candidate in candidates where seen.insert(candidate.standardizedFileURL.path).inserted {
                if FileManager.default.fileExists(atPath: candidate.path) {
                    try FileManager.default.removeItem(at: candidate)
                }
            }
            if item.fileName.lowercased().hasSuffix(".m3u8") {
                let stem = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
                let prefix = stem + "-segment-"
                let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for companion in files where companion.lastPathComponent.hasPrefix(prefix) {
                    try FileManager.default.removeItem(at: companion)
                }
            }
        } catch {
            mutate(id) { $0.message = "Không xoá được tệp trong thư mục tải xuống. Hãy kiểm tra quyền truy cập thư mục rồi thử lại." }
            save()
            return
        }
        items.removeAll { $0.id == id }
        removeCachedPoster(for: item)
        removeCachedSubtitles(for: item)
        save(); pump(); pumpPosterCacheQueue(); pumpSubtitleCacheQueue()
    }

    /// Xoá tệp trực tiếp theo đường dẫn (dùng cho trình duyệt tệp).
    @discardableResult
    func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            if let item = item(fileName: url.lastPathComponent) { remove(item.id) }
            return true
        } catch {
            return false
        }
    }

    /// Tải cả một nguồn: dùng cho nút "Tải tất cả" trong danh sách tập.
    /// Xếp hàng nhiều tập cùng lúc.
    ///
    /// Trước khi xếp hàng, ước tính dung lượng của một tập từ playlist của tập đầu
    /// rồi nhân cho số tập; nếu vượt dung lượng trống (kể cả phần đang chờ tải) thì
    /// không nhận và trả về lời báo để màn hình hiển thị.
    func enqueueAll(movie: Movie, serverName: String, episodes: [MovieEpisode]) async -> String? {
        let downloadable = episodes.filter { $0.playbackURL != nil }
        guard let first = downloadable.first else {
            return "Nguồn này không có tập nào tải được về máy."
        }
        var perEpisode: Int64 = 0
        if let url = first.playbackURL {
            let session = self.session
            if let resolved = try? await Self.resolvePlaylist(
                try await Self.text(from: try await Self.fetch(url, session: session)),
                base: url,
                fetch: { try await Self.fetch($0, session: session) }
            ), resolved.bandwidth > 0, resolved.duration > 0 {
                let estimate = Double(resolved.bandwidth) / 8 * resolved.duration
                if estimate.isFinite, estimate > 0, estimate < Double(Int64.max) {
                    perEpisode = Int64(estimate)
                }
            }
        }
        let episodeCount = Int64(downloadable.count)
        let needed = perEpisode > 0 && episodeCount > 0 && perEpisode > Int64.max / episodeCount
            ? Int64.max
            : perEpisode * episodeCount
        let reserved = reservedBytes
        let totalNeeded = needed > Int64.max - reserved ? Int64.max : needed + reserved
        let available = freeBytes
        if needed > 0, totalNeeded > available {
            return "Không đủ dung lượng: \(downloadable.count) tập có link cần khoảng \(auroraByteText(needed)), máy còn \(auroraByteText(available)). Hãy chọn bớt tập, hoặc tải lượng phim thấp hơn dung lượng còn trống."
        }
        for episode in downloadable { enqueue(movie: movie, serverName: serverName, episode: episode) }
        let skipped = episodes.count - downloadable.count
        if skipped > 0 {
            return "Đã thêm \(downloadable.count) tập vào hàng đợi. Bỏ qua \(skipped) tập vì chưa có link HLS tải được."
        }
        return nil
    }

    // MARK: - Tải

    private func acceptPackage(id: String, at location: URL) async {
        guard let current = item(id: id), current.phase == .downloading else { nativeDownloads.forget(id: id); return }
        let reportedPath = Self.storedAssetPath(for: location)
        estimateTasks[id]?.cancel(); estimateTasks[id] = nil
        progressSamples[id] = nil
        do {
            let targetName = current.fileName
            let target = location.standardizedFileURL
            let asset = AVURLAsset(url: target)
            let playable = try await asset.load(.isPlayable)
            guard target.pathExtension.lowercased() == "movpkg",
                  playable,
                  asset.assetCache?.isPlayableOffline == true,
                  OfflinePlaybackSupport.validatePlayableFile(target),
                  let storedPath = Self.storedAssetPath(for: target) else {
                throw DownloadError.invalidOutput
            }
            let bytes = await Self.directorySize(target)
            mutate(id) { $0.fileName = targetName; $0.nativeAssetPath = storedPath; $0.phase = .finished; $0.doneSegments = 0; $0.totalSegments = 0; $0.receivedBytes = bytes; $0.totalBytes = bytes; $0.nativeProgress = nil; $0.speed = nil; $0.estimateUnavailable = false; $0.message = nil }
            nativeDownloads.forget(id: id); tasks[id]?.cancel(); tasks[id] = nil
            save(force: true)
            pump()
            if let completed = item(id: id) {
                cachePoster(for: completed)
                retrySubtitleCaches(for: id)
            }
            pumpPosterCacheQueue(); pumpSubtitleCacheQueue()
        } catch {
            nativeDownloads.forget(id: id)
            tasks[id]?.cancel(); tasks[id] = nil
            mutate(id) { $0.nativeAssetPath = reportedPath; $0.phase = .failed; $0.nativeProgress = nil; $0.speed = nil; $0.message = "Không xác minh hoặc lưu được package HLS: \(error.localizedDescription)" }
            save(force: true); pump(); pumpPosterCacheQueue(); pumpSubtitleCacheQueue()
        }
    }

    private nonisolated static func directorySize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            return enumerator.compactMap { $0 as? URL }.reduce(Int64(0)) { total, file in
                let size = Int64(max(0, (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                return total > Int64.max - size ? Int64.max : total + size
            }
        }.value
    }

    /// Hàm tĩnh, chỉ nhận `URLSession` (Sendable) nên tác vụ tải chạy ngoài
    /// main actor — giao diện không bị ảnh hưởng khi tải nhiều phân đoạn.
    nonisolated private static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    // MARK: - Playlist

    private struct ResolvedPlaylist {
        var segments: [URL]
        var durations: [Double]
        var encrypted: Bool
        var unsupportedFeatures: Bool
        /// Tổng thời lượng (giây) tính từ các thẻ #EXTINF.
        var duration: Double
        /// Băng thông biến thể đã chọn (bit/giây), 0 nếu playlist không khai.
        var bandwidth: Int
    }

    /// Trả về danh sách phân đoạn. Nếu là playlist tổng (có `#EXT-X-STREAM-INF`)
    /// thì chọn biến thể băng thông cao nhất rồi đọc tiếp playlist đó.
    nonisolated private static func resolvePlaylist(
        _ text: String,
        base: URL,
        fetch: (URL) async throws -> Data
    ) async throws -> ResolvedPlaylist {
        var body = text
        var currentBase = base
        var depth = 0
        var bandwidth = 0
        while body.contains("#EXT-X-STREAM-INF") && depth < 3 {
            guard let variant = bestVariant(in: body, base: currentBase) else { break }
            bandwidth = Self.variantBandwidth(in: body, base: currentBase)
            body = try await Self.text(from: try await fetch(variant))
            currentBase = variant
            depth += 1
        }
        let duration = body.split(separator: "\n").reduce(0.0) { total, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXTINF") else { return total }
            let value = line.dropFirst("#EXTINF:".count).split(separator: ",").first ?? ""
            return total + (Double(value.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
        let encrypted = body.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#EXT-X-KEY") && !trimmed.contains("METHOD=NONE")
        }
        let unsupportedFeatures = body.split(separator: "\n").contains { line in
            let tag = line.trimmingCharacters(in: .whitespaces)
            return tag.hasPrefix("#EXT-X-MAP") || tag.hasPrefix("#EXT-X-BYTERANGE") || tag.hasPrefix("#EXT-X-I-FRAMES-ONLY")
        }
        var segments: [URL] = []
        var durations: [Double] = []
        var pendingDuration = 0.0
        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF:") {
                let raw = line.dropFirst("#EXTINF:".count).split(separator: ",").first ?? ""
                pendingDuration = Double(raw) ?? 0
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let url = URL(string: line, relativeTo: currentBase)?.absoluteURL {
                segments.append(url); durations.append(pendingDuration); pendingDuration = 0
            }
        }
        return ResolvedPlaylist(segments: segments, durations: durations, encrypted: encrypted, unsupportedFeatures: unsupportedFeatures, duration: duration, bandwidth: bandwidth)
    }

    /// Ưu tiên AVERAGE-BANDWIDTH của biến thể đã chọn để ước tính dung lượng;
    /// dùng BANDWIDTH làm phương án dự phòng khi nguồn không khai báo trung bình.
    nonisolated private static func variantBandwidth(in text: String, base: URL) -> Int {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let selected = bestVariant(in: text, base: base) else { return 0 }
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            guard index + 1 < lines.count, !lines[index + 1].hasPrefix("#") else { continue }
            guard let candidate = URL(string: lines[index + 1], relativeTo: base)?.absoluteURL,
                  candidate == selected else { continue }
            return Int(attribute("AVERAGE-BANDWIDTH", in: line) ?? "")
                ?? Int(attribute("BANDWIDTH", in: line) ?? "")
                ?? 0
        }
        return 0
    }

    /// Biến thể có BANDWIDTH lớn nhất — tương ứng chất lượng cao nhất có sẵn.
    nonisolated private static func bestVariant(in text: String, base: URL) -> URL? {
        var best: (bandwidth: Int, url: URL)?
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            let bandwidth = Int(Self.attribute("BANDWIDTH", in: line) ?? "") ?? 0
            guard index + 1 < lines.count else { continue }
            let next = lines[index + 1]
            guard !next.hasPrefix("#"), let url = URL(string: next, relativeTo: base)?.absoluteURL else { continue }
            if let current = best {
                if bandwidth > current.bandwidth { best = (bandwidth, url) }
            } else {
                best = (bandwidth, url)
            }
        }
        return best?.url
    }

    nonisolated private static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name)=") else { return nil }
        let rest = line[range.upperBound...]
        return rest.split(separator: ",").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    nonisolated private static func text(from data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw DownloadError.playlist
        }
        return value
    }

    // MARK: - Lưu trữ

    private func mutate(_ id: String, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        items[index].updatedAt = Date()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([Item].self, from: data) else { return }
        // Native tasks use a background session but their mapping is process-local.
        // Interrupted entries must be retried; the session cancels old unmapped tasks.
        items = stored.map { item in
            var copy = item
            // JSON can contain representable but nonsensical counters. Normalize
            // them before views format progress or storage estimates.
            copy.receivedBytes = max(0, copy.receivedBytes)
            copy.totalBytes = max(0, copy.totalBytes)
            copy.doneSegments = max(0, copy.doneSegments)
            copy.totalSegments = max(0, copy.totalSegments)
            if let speed = copy.speed, !speed.isFinite || speed < 0 { copy.speed = nil }
            if let progress = copy.nativeProgress, !progress.isFinite { copy.nativeProgress = nil }
            if let duration = copy.durationSeconds, !duration.isFinite || duration < 0 { copy.durationSeconds = nil }
            if let bandwidth = copy.bandwidth, bandwidth < 0 { copy.bandwidth = nil }
            if copy.phase != .finished {
                copy.nativeProgress = nil; copy.speed = nil; copy.doneSegments = 0; copy.totalSegments = 0
            }
            if copy.phase == .downloading || copy.phase == .waiting { copy.phase = .failed; copy.message = "Tải native chưa hoàn tất khi app đóng; hãy tải lại." }
            let isNativePackage = copy.fileName.lowercased().hasSuffix(".movpkg")
            let packageCandidates = [
                Self.assetURL(from: copy.nativeAssetPath),
                Optional(root.appendingPathComponent(copy.fileName, isDirectory: true)),
                Optional(metadataRoot.appendingPathComponent("Downloads", isDirectory: true).appendingPathComponent(copy.fileName, isDirectory: true))
            ].compactMap { $0 }
            let package = packageCandidates.first(where: { OfflinePlaybackSupport.validatePlayableFile($0) })
            if copy.phase == .finished && (!isNativePackage || package == nil) {
                copy.phase = .unsupported
                copy.message = "Bản tải offline không còn khả dụng. Hãy xoá mục này rồi tải lại."
            } else if copy.fileName.lowercased().hasSuffix(".m3u8") || copy.fileName.lowercased().hasSuffix(".ts") {
                copy.phase = .unsupported
                copy.message = "Tệp tải đời cũ không phải package AVFoundation. Hãy xoá và tải lại bằng native HLS."
            }
            return copy
        }
        save(force: true)
        if isConnected {
            for item in items where item.phase == .finished {
                cachePoster(for: item)
                retrySubtitleCaches(for: item.id)
            }
        }
    }

    private func removeCachedPoster(for item: Item) {
        posterTasks[item.id]?.cancel()
        posterTasks[item.id] = nil
        pendingPosterCacheIDSet.remove(item.id)
        failedPosterCacheIDs.remove(item.id)
        if let filename = posterCacheFilename(for: item) {
            try? FileManager.default.removeItem(at: posterCacheRoot.appendingPathComponent(filename))
        }
        pumpPosterCacheQueue()
    }

    private func removeCachedSubtitles(for item: Item) {
        for record in item.subtitleTracks ?? [] {
            let key = SubtitleCacheKey(itemID: item.id, recordID: record.id)
            subtitleTasks[key]?.cancel()
            subtitleTasks[key] = nil
            pendingSubtitleCacheKeySet.remove(key)
            failedSubtitleCacheKeys.remove(key)
            let filename = safeSubtitleFilename(record.cacheFilename) ?? subtitleDestination(for: item, record: record).lastPathComponent
            try? FileManager.default.removeItem(at: subtitleCacheRoot.appendingPathComponent(filename))
        }
        pumpSubtitleCacheQueue()
    }

    private func mergeSubtitleMetadata(id: String, tracks: [MovieEpisodeSubtitleTrack]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let incoming = Self.cachedSubtitleMetadata(from: tracks)
        guard !incoming.isEmpty else { return }
        var existing = items[index].subtitleTracks ?? []
        for record in incoming {
            if let position = existing.firstIndex(where: { $0.id == record.id }) {
                existing[position].language = record.language
                existing[position].sourceURL = record.sourceURL
            } else if existing.count < Self.maxSubtitleTracks {
                existing.append(record)
            }
        }
        items[index].subtitleTracks = Array(existing.prefix(Self.maxSubtitleTracks))
        items[index].updatedAt = Date()
        save(force: true)
    }

    private static func cachedSubtitleMetadata(from tracks: [MovieEpisodeSubtitleTrack]) -> [CachedSubtitle] {
        var result: [CachedSubtitle] = []
        var seen = Set<String>()
        for track in tracks.prefix(maxSubtitleTracks) {
            let language = track.language.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !language.isEmpty, let url = track.subtitleURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let sourceURL = url.absoluteString
            let id = "\(language)|\(sourceURL)"
            guard seen.insert(id).inserted else { continue }
            result.append(CachedSubtitle(id: id, language: language, sourceURL: sourceURL, cacheFilename: nil))
        }
        return result
    }

    private func safeSubtitleFilename(_ filename: String?) -> String? {
        guard let filename, !filename.isEmpty, URL(fileURLWithPath: filename).lastPathComponent == filename else { return nil }
        return filename
    }

    private func subtitleDestination(for item: Item, record: CachedSubtitle) -> URL {
        let stem = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        let safeStem = Self.safeComponent(stem)
        let extensionName = URL(string: record.sourceURL)?.pathExtension.lowercased()
        let safeExtension = extensionName == "srt" ? "srt" : "vtt"
        let filename = "\(safeStem)-\(Self.stableHash(record.id)).\(safeExtension)"
        return subtitleCacheRoot.appendingPathComponent(filename)
    }

    private func pumpSubtitleCacheQueue() {
        guard isConnected, !hasForegroundDownloadWork else { return }
        while subtitleTasks.count < maxConcurrentSubtitleCaches, pendingSubtitleCacheCursor < pendingSubtitleCacheKeys.count {
            let key = pendingSubtitleCacheKeys[pendingSubtitleCacheCursor]
            pendingSubtitleCacheCursor += 1
            guard pendingSubtitleCacheKeySet.remove(key) != nil else { continue }
            guard let item = item(id: key.itemID), item.phase == .finished,
                  let record = item.subtitleTracks?.first(where: { $0.id == key.recordID }) else { continue }
            startSubtitleCache(for: item, record: record, key: key)
        }
        if pendingSubtitleCacheCursor >= pendingSubtitleCacheKeys.count {
            pendingSubtitleCacheKeys.removeAll(keepingCapacity: true)
            pendingSubtitleCacheCursor = 0
        } else if pendingSubtitleCacheCursor >= 64, pendingSubtitleCacheCursor * 2 >= pendingSubtitleCacheKeys.count {
            pendingSubtitleCacheKeys.removeFirst(pendingSubtitleCacheCursor)
            pendingSubtitleCacheCursor = 0
        }
    }

    private func startSubtitleCache(for item: Item, record: CachedSubtitle, key: SubtitleCacheKey) {
        guard isConnected,
              let sourceURL = URL(string: record.sourceURL),
              ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? "") else {
            failedSubtitleCacheKeys.insert(key)
            return
        }
        let destination = subtitleDestination(for: item, record: record)
        if record.cacheFilename == destination.lastPathComponent, Self.subtitleFileSize(destination) != nil { return }
        guard subtitleTasks[key] == nil else { return }
        let session = self.session
        subtitleTasks[key] = Task { [weak self, session] in
            let success = await Self.downloadSubtitle(from: sourceURL, to: destination, session: session)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.subtitleTasks[key] = nil
            if !success {
                // Subtitle failure is intentionally silent: it must not turn a
                // valid movie download into a failed item.
                self.failedSubtitleCacheKeys.insert(key)
                self.pumpSubtitleCacheQueue()
                return
            }
            self.updateSubtitleFilename(itemID: item.id, recordID: record.id, filename: destination.lastPathComponent)
            self.pumpSubtitleCacheQueue()
        }
    }

    private func updateSubtitleFilename(itemID: String, recordID: String, filename: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              var records = items[index].subtitleTracks,
              let recordIndex = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[recordIndex].cacheFilename = filename
        items[index].subtitleTracks = records
        items[index].updatedAt = Date()
        save(force: true)
    }

    private static func downloadSubtitle(from url: URL, to destination: URL, session: URLSession) async -> Bool {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("text/vtt,text/srt,application/srt,application/x-subrip,text/plain,application/octet-stream;q=0.9", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            // First land the response in a temporary file. A bad subtitle URL
            // must not allocate an unbounded body in memory.
            let (temporaryURL, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  ["text/vtt", "text/plain", "application/octet-stream", "application/x-subrip", "text/srt", "application/srt"].contains(http.mimeType?.lowercased() ?? "application/octet-stream"),
                  !Task.isCancelled else { return false }
            let copied = await Task.detached(priority: .utility) {
                guard Self.subtitleFileSize(temporaryURL) != nil,
                      let data = try? Data(contentsOf: temporaryURL),
                      Self.validSubtitlePayload(data) else { return false }
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: [.atomic])
                    return Self.subtitleFileSize(destination) != nil
                } catch {
                    return false
                }
            }.value
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                return false
            }
            return copied
        } catch {
            return false
        }
    }

    nonisolated private static func subtitleFileSize(_ url: URL) -> Int? {
        let sizeLimit = 8 * 1024 * 1024
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= sizeLimit else { return nil }
        return size
    }

    nonisolated private static func validSubtitlePayload(_ data: Data) -> Bool {
        guard let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return false }
        let lines = source.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cueCount = 0
        var textCount = 0
        var afterCue = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                let right = parts.count > 1 ? parts[1].split(separator: " ", maxSplits: 1).first.map(String.init) ?? "" : ""
                guard parts.count > 1, validTimestamp(parts[0]), validTimestamp(right) else { continue }
                cueCount += 1
                afterCue = true
            } else if afterCue, !line.isEmpty, !line.hasPrefix("NOTE") {
                textCount += 1
            } else if line.isEmpty {
                afterCue = false
            }
        }
        let header = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cueCount > 0 && textCount > 0 && (header == "WEBVTT" || cueCount > 0)
    }

    nonisolated private static func validTimestamp(_ raw: String) -> Bool {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (parts.count == 2 || parts.count == 3), parts.allSatisfy({ Double($0) != nil }) else { return false }
        let values = parts.compactMap { Double($0) }
        return values.allSatisfy { $0 >= 0 }
    }

    private static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleaned).prefix(80).isEmpty ? "subtitle" : String(String(cleaned).prefix(80))
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return String(format: "%016llx", hash)
    }

    /// Fetch independently and cap retained artwork to 5 MiB without buffering an unbounded response.
    private func cachePoster(for item: Item) {
        guard isConnected, item.phase == .finished, posterURL(for: item) == nil,
              let raw = item.poster, let url = URL(string: raw, relativeTo: CinemaAPI.baseURL)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              posterTasks[item.id] == nil,
              !failedPosterCacheIDs.contains(item.id) else { return }
        guard posterCacheFilename(for: item) != nil else { return }
        if pendingPosterCacheIDSet.insert(item.id).inserted { pendingPosterCacheIDs.append(item.id) }
        pumpPosterCacheQueue()
    }

    private func pumpPosterCacheQueue() {
        guard isConnected, !hasForegroundDownloadWork else { return }
        while posterTasks.count < maxConcurrentPosterCaches, pendingPosterCacheCursor < pendingPosterCacheIDs.count {
            let id = pendingPosterCacheIDs[pendingPosterCacheCursor]
            pendingPosterCacheCursor += 1
            guard pendingPosterCacheIDSet.remove(id) != nil else { continue }
            guard let current = item(id: id), current.phase == .finished,
                  !failedPosterCacheIDs.contains(id), posterURL(for: current) == nil,
                  let raw = current.poster,
                  let url = URL(string: raw, relativeTo: CinemaAPI.baseURL)?.absoluteURL,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            guard let filename = posterCacheFilename(for: current) else { continue }
            startPosterCache(for: current, url: url, filename: filename)
        }
        if pendingPosterCacheCursor >= pendingPosterCacheIDs.count {
            pendingPosterCacheIDs.removeAll(keepingCapacity: true)
            pendingPosterCacheCursor = 0
        } else if pendingPosterCacheCursor >= 64, pendingPosterCacheCursor * 2 >= pendingPosterCacheIDs.count {
            pendingPosterCacheIDs.removeFirst(pendingPosterCacheCursor)
            pendingPosterCacheCursor = 0
        }
    }

    private func startPosterCache(for item: Item, url: URL, filename: String) {
        let session = self.session
        let destination = posterCacheRoot.appendingPathComponent(filename)
        var succeeded = false
        posterTasks[item.id] = Task { [weak self, session] in
            var temporaryURL: URL?
            defer {
                if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
                self?.posterTasks[item.id] = nil
                if !succeeded, self?.item(id: item.id) != nil {
                    self?.failedPosterCacheIDs.insert(item.id)
                }
                self?.pumpPosterCacheQueue()
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (downloadedURL, response) = try await session.download(for: request)
                temporaryURL = downloadedURL
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      http.mimeType?.lowercased().hasPrefix("image/") == true,
                      let values = try? downloadedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      let size = values.fileSize, size > 0, size <= 5 * 1024 * 1024,
                      !Task.isCancelled, let self,
                      let current = self.item(id: item.id),
                      self.posterCacheFilename(for: current) == filename else { return }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: downloadedURL, to: destination)
                self.posterCacheRevision &+= 1
                self.save()
                succeeded = true
            } catch { /* Artwork is optional; never delay movie downloads. */ }
        }
    }

    /// Ghi danh sách tải xuống xuống đĩa.
    ///
    /// Tiến trình AVFoundation cập nhật liên tục; ghi tối đa 3 giây một lần để
    /// tránh ghi metadata quá dày. Thay đổi trạng thái quan trọng ghi ngay.
    private func save(force: Bool = false) {
        let now = Date()
        if !force, now.timeIntervalSince(lastSaveAt) < 3 { return }
        lastSaveAt = now
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private var hasForegroundDownloadWork: Bool {
        !tasks.isEmpty || items.contains { $0.phase == .waiting }
    }

    private enum DownloadError: LocalizedError {
        case empty, storage, playlist, invalidOutput, http(Int)

        var errorDescription: String? {
            switch self {
            case .empty: "Nguồn phim không có phân đoạn nào để tải."
            case .storage: "Không ghi được vào bộ nhớ máy."
            case .playlist: "Không đọc được danh sách phân đoạn của nguồn phim."
            case .invalidOutput: "Không xác thực được playlist tải xuống. Hãy tải lại tập phim."
            case .http(let code): code == 404 ? "Nguồn phim đã hết hạn, hãy chọn nguồn khác." : "Máy chủ nguồn phim trả lỗi \(code)."
            }
        }
    }

    private static func packageName(movie: String, episode: String, source: String) -> String {
        let raw = "\(movie)-\(episode)-\(source)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(String(cleaned).prefix(100)) + ".movpkg"
    }
}

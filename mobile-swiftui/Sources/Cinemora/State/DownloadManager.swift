import AVFoundation
import Foundation
import Network
import UIKit

/// Quản lý phim tải về để xem khi không có wifi.
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

    struct Item: Identifiable, Codable, Equatable {
        var id: String
        var movieSlug: String
        var movieName: String
        var poster: String?
        var serverName: String
        var episodeName: String
        var episodeSlug: String
        var quality: String?
        var sourceURL: String
        var fileName: String
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
        /// Tốc độ tải trung bình của phiên hiện tại (byte/giây).
        var speed: Double?
        /// Thời điểm bắt đầu tải phiên hiện tại.
        var startedAt: Date?

        var progress: Double {
            if totalSegments > 0 { return min(1, max(0, Double(doneSegments) / Double(totalSegments))) }
            if totalBytes > 0 { return min(1, max(0, Double(receivedBytes) / Double(totalBytes))) }
            return phase == .finished ? 1 : 0
        }
        var isRunning: Bool { phase == .downloading || phase == .waiting }

        /// Tổng dung lượng ước tính của cả tập phim. Khi đã tải đủ phân đoạn thì
        /// suy ra từ số đo thực tế (chính xác nhất); trước đó dùng băng thông khai
        /// báo trong playlist nhân với tổng thời lượng.
        var estimatedTotalBytes: Int64 {
            if phase == .finished { return max(receivedBytes, 0) }
            var measured: Int64 = 0
            if doneSegments >= 3, receivedBytes > 0, totalSegments > 0 {
                let estimate = Double(receivedBytes) / Double(doneSegments) * Double(totalSegments)
                if estimate.isFinite, estimate > 0, estimate < Double(Int64.max) {
                    measured = Int64(estimate)
                }
            }
            var declared: Int64 = 0
            if let bandwidth, bandwidth > 0, let durationSeconds, durationSeconds > 0 {
                let estimate = Double(bandwidth) / 8 * durationSeconds
                if estimate.isFinite, estimate > 0, estimate < Double(Int64.max) {
                    declared = Int64(estimate)
                }
            }
            if measured > 0 && declared > 0 {
                // Playlist tổng có thể khai băng thông gấp nhiều lần thực tế; khi
                // hai con số lệch quá xa thì tin vào số đo.
                return Double(measured) > Double(declared) * 3 ? measured : max(measured, declared)
            }
            return measured > 0 ? measured : declared
        }

        /// "1,2 GB / 50 GB" — đúng dạng người dùng cần thấy.
        var sizeText: String {
            let done = auroraByteText(receivedBytes)
            let total = estimatedTotalBytes
            guard total > 0 else { return done }
            return "\(done) / \(auroraByteText(total))"
        }

        var percentText: String { "\(Int((min(1, max(0, progress)) * 100).rounded()))%" }

        var speedText: String {
            guard let speed, speed.isFinite, speed > 0, speed < Double(Int64.max) else { return "" }
            return "\(auroraByteText(Int64(speed)))/s"
        }

        /// Thời gian còn lại ước tính, chỉ hiện khi đã có số đo tốc độ.
        var etaText: String {
            guard let speed, speed.isFinite, speed > 0, phase == .downloading else { return "" }
            let remaining = Double(max(estimatedTotalBytes, 0)) - Double(max(receivedBytes, 0))
            guard remaining > 0 else { return "" }
            let estimate = remaining / speed
            guard estimate.isFinite else { return "còn rất lâu" }
            guard estimate < Double(Int.max) else { return "còn rất lâu" }
            let seconds = Int(estimate)
            if seconds < 60 { return "còn <1 phút" }
            if seconds < 3600 { return "còn ~\(seconds / 60) phút" }
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "còn ~\(hours) giờ \(minutes) phút"
        }

        /// Tệp có sẵn trong máy và đang chờ xoá hay không.
        var canStart: Bool { phase == .paused || phase == .failed || phase == .waiting }
    }

    private(set) var items: [Item] = []
    /// Thông báo cho màn cài đặt khi thư mục đổi hoặc quyền truy cập bị thu hồi.
    var folderMessage: String?
    /// Máy đang dùng Wi-Fi hay không. Phim rất nặng nên chỉ tải qua Wi-Fi.
    private(set) var isWiFi = false
    /// Lời nhắc hiện trên màn Tải xuống khi cần Wi-Fi để chạy tiếp.
    var wifiNotice: String?
    private let pathMonitor = NWPathMonitor()
    private var lastSaveAt: Date = .distantPast
    private static let wifiMessage = "Cần Wi-Fi để tải phim. Nếu bị ngắt, bản tải dở phải bắt đầu lại từ đầu."

    private var tasks: [String: Task<Void, Never>] = [:]
    /// Số tập tải song song tối đa.
    private let maxConcurrent = 2
    /// Thư mục mặc định nằm trong Documents để hiện được trong app Tệp.
    private let defaultRoot: URL
    /// Nơi lưu danh sách tải xuống (dữ liệu nội bộ, không phải phim).
    private let metadataRoot: URL
    private var customBookmark: Data?
    private var scopedRoot: URL?
    private var storeURL: URL { metadataRoot.appendingPathComponent("downloads.json") }
    private let session: URLSession
    private let nativeDownloads = NativeHLSDownloadSession()
    private static let bookmarkKey = "cinemora.downloadFolderBookmark"

    /// Thư mục đang dùng để chứa phim tải về.
    var root: URL { scopedRoot ?? defaultRoot }
    var isUsingDefaultFolder: Bool { scopedRoot == nil }
    var folderName: String { isUsingDefaultFolder ? "Cinemora/Downloads" : root.lastPathComponent }
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
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Cinemora/1.0 (iOS)"]
        session = URLSession(configuration: configuration)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            let online = path.status == .satisfied
            Task { @MainActor in self?.applyNetwork(wifi: wifi, online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.cinemora.downloads.network"))
        customBookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey)
        resolveCustomFolder()
        // Bản cũ lưu trong Application Support — chuyển sang thư mục mặc định mới.
        moveFiles(into: defaultRoot, from: [metadataRoot.appendingPathComponent("Downloads", isDirectory: true)])
        load()
        nativeDownloads.onProgress = { [weak self] id, fraction in
            Task { @MainActor in
                guard let self, let item = self.item(id: id), item.phase == .downloading else { return }
                self.mutate(id) {
                    // Keep only native fractional progress; AVFoundation doesn't
                    // report byte/segment counts through this callback.
                    $0.totalSegments = 10_000
                    $0.doneSegments = Int(max(0, min(1, fraction)) * 10_000)
                    $0.receivedBytes = 0; $0.totalBytes = 0
                }
                self.save()
            }
        }
        nativeDownloads.onPackage = { [weak self] id, location in
            Task { @MainActor in await self?.acceptPackage(id: id, at: location) }
        }
        nativeDownloads.onFailure = { [weak self] id, error in
            Task { @MainActor in
                guard let self, self.item(id: id)?.phase == .downloading else { return }
                self.mutate(id) { $0.phase = .failed; $0.receivedBytes = 0; $0.totalBytes = 0; $0.message = error.localizedDescription }
                self.tasks[id]?.cancel(); self.tasks[id] = nil
                self.save(force: true); self.pump()
            }
        }
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
        for item in items where item.phase == .downloading || item.phase == .waiting {
            pause(item.id)
        }
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
                let isManaged = ext == "movpkg" || ext == "m3u8" || ext == "ts"
                guard isManaged else { continue }
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
        let package = root.appendingPathComponent(item.fileName, isDirectory: true)
        guard item.fileName.lowercased().hasSuffix(".movpkg"),
              OfflinePlaybackSupport.validatePlayableFile(package) else { return nil }
        return package
    }

    /// Mô tả đúng cách downloader lưu HLS để hiển thị trên màn Đã tải.
    func offlineStorageText(for item: Item) -> String {
        return "Tệp \(item.fileName)"
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
        guard let url = episode.playbackURL else { return nil }
        let slug = episode.slug.isEmpty ? episode.name : episode.slug
        let id = "\(movie.slug)|\(serverName)|\(slug)"
        if let index = items.firstIndex(where: { $0.id == id }) {
            if items[index].phase != .finished { start(id) }
            return items[index]
        }
        let safeName = Self.packageName(movie: movie.slug, episode: slug, source: serverName)
        let item = Item(
            id: id,
            movieSlug: movie.slug,
            movieName: movie.name,
            poster: movie.poster,
            serverName: serverName,
            episodeName: episode.name,
            episodeSlug: slug,
            quality: quality,
            sourceURL: url.absoluteString,
            fileName: safeName,
            phase: .waiting,
            receivedBytes: 0,
            totalBytes: 0,
            doneSegments: 0,
            totalSegments: 0,
            message: nil,
            updatedAt: Date()
        )
        items.insert(item, at: 0)
        save()
        start(id)
        return item
    }

    func start(_ id: String) {
        guard tasks[id] == nil, let item = item(id: id), item.phase != .finished else { return }
        guard isWiFi else {
            mutate(id) { $0.phase = .waiting; $0.message = Self.wifiMessage }
            wifiNotice = Self.wifiMessage; save(force: true); return
        }
        guard tasks.count < maxConcurrent else {
            mutate(id) { $0.phase = .waiting }; save(); return
        }
        guard let url = URL(string: item.sourceURL), url.scheme?.lowercased().hasPrefix("http") == true else {
            mutate(id) { $0.phase = .failed; $0.message = "Đường dẫn HLS không hợp lệ." }; save(force: true); return
        }
        mutate(id) { $0.phase = .downloading; $0.message = nil; $0.receivedBytes = 0; $0.totalBytes = 0; $0.startedAt = Date() }
        let packageURL = root.appendingPathComponent(item.fileName, isDirectory: true)
        guard nativeDownloads.start(id: id, url: url, title: "\(item.movieName) — \(item.episodeName)", destination: packageURL) else {
            mutate(id) { $0.phase = .failed; $0.message = "Không tạo được AVAssetDownloadTask cho nguồn HLS này." }
            save(force: true); return
        }
        tasks[id] = Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)) }
            _ = self
        }
        save(force: true)
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
        guard let item = item(id: id), item.phase == .downloading || item.phase == .waiting else { return }
        nativeDownloads.cancel(id: id)
        tasks[id]?.cancel(); tasks[id] = nil
        mutate(id) { $0.phase = .paused; $0.receivedBytes = 0; $0.totalBytes = 0; $0.message = "Đã huỷ tải. Bấm Tải lại để bắt đầu lại từ đầu." }
        save(force: true); pump()
    }

    func retry(_ id: String) {
        guard let item = item(id: id) else { return }
        let storedURL = root.appendingPathComponent(item.fileName, isDirectory: item.fileName.lowercased().hasSuffix(".movpkg"))
        if FileManager.default.fileExists(atPath: storedURL.path) { try? FileManager.default.removeItem(at: storedURL) }
        mutate(id) { $0.fileName = Self.packageName(movie: $0.movieSlug, episode: $0.episodeSlug, source: $0.serverName); $0.phase = .waiting; $0.receivedBytes = 0; $0.totalBytes = 0; $0.message = nil }
        start(id)
    }

    /// Rời Wi-Fi thì huỷ tác vụ để không dùng dữ liệu di động. Tác vụ đã dừng
    /// không giữ segment resume; người dùng tải lại toàn bộ khi sẵn sàng.
    private func applyNetwork(wifi: Bool, online: Bool) {
        let wasWiFi = isWiFi
        isWiFi = wifi && online
        guard isWiFi else {
            for item in items where item.phase == .downloading { pause(item.id) }
            if items.contains(where: { $0.phase == .waiting || $0.phase == .paused }) {
                wifiNotice = Self.wifiMessage
            }
            return
        }
        wifiNotice = nil
        if !wasWiFi {
            pump()
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
        tasks[id]?.cancel()
        tasks[id] = nil
        let file = root.appendingPathComponent(item.fileName)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
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
        save()
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
        guard let first = episodes.first(where: { $0.playbackURL != nil }) else {
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
        let episodeCount = Int64(episodes.count)
        let needed = perEpisode > 0 && episodeCount > 0 && perEpisode > Int64.max / episodeCount
            ? Int64.max
            : perEpisode * episodeCount
        let reserved = reservedBytes
        let totalNeeded = needed > Int64.max - reserved ? Int64.max : needed + reserved
        let available = freeBytes
        if needed > 0, totalNeeded > available {
            return "Không đủ dung lượng: \(episodes.count) tập cần khoảng \(auroraByteText(needed)), máy còn \(auroraByteText(available)). Hãy chọn bớt tập, hoặc tải lượng phim thấp hơn dung lượng còn trống."
        }
        for episode in episodes { enqueue(movie: movie, serverName: serverName, episode: episode) }
        return nil
    }

    // MARK: - Tải

    private func acceptPackage(id: String, at location: URL) async {
        guard let current = item(id: id), current.phase == .downloading else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let targetName = current.fileName
            let target = location
            guard target.standardizedFileURL == root.appendingPathComponent(targetName, isDirectory: true).standardizedFileURL else {
                throw DownloadError.invalidOutput
            }
            let playable = try await AVURLAsset(url: target).load(.isPlayable)
            guard playable, OfflinePlaybackSupport.validatePlayableFile(target) else { throw DownloadError.invalidOutput }
            let bytes = await Self.directorySize(target)
            mutate(id) { $0.fileName = targetName; $0.phase = .finished; $0.doneSegments = 0; $0.totalSegments = 0; $0.receivedBytes = bytes; $0.totalBytes = bytes; $0.message = nil }
            nativeDownloads.forget(id: id); tasks[id]?.cancel(); tasks[id] = nil
            save(force: true); pump()
        } catch {
            nativeDownloads.forget(id: id)
            tasks[id]?.cancel(); tasks[id] = nil
            mutate(id) { $0.phase = .failed; $0.message = "Không xác minh hoặc lưu được package HLS: \(error.localizedDescription)" }
            save(force: true); pump()
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
            bandwidth = max(bandwidth, Self.variantBandwidth(in: body, base: currentBase))
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

    /// Băng thông của biến thể tốt nhất trong playlist tổng.
    nonisolated private static func variantBandwidth(in text: String, base: URL) -> Int {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var best = 0
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            guard index + 1 < lines.count, !lines[index + 1].hasPrefix("#") else { continue }
            best = max(best, Int(attribute("BANDWIDTH", in: line) ?? "") ?? 0)
        }
        return best
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
        // This implementation uses foreground sessions without task restoration.
        // Interrupted work must be retried; valid persisted packages remain finished.
        items = stored.map { item in
            var copy = item
            // JSON can contain representable but nonsensical counters. Normalize
            // them before views format progress or storage estimates.
            copy.receivedBytes = max(0, copy.receivedBytes)
            copy.totalBytes = max(0, copy.totalBytes)
            copy.doneSegments = max(0, copy.doneSegments)
            copy.totalSegments = max(0, copy.totalSegments)
            if let speed = copy.speed, !speed.isFinite || speed < 0 { copy.speed = nil }
            if let duration = copy.durationSeconds, !duration.isFinite || duration < 0 { copy.durationSeconds = nil }
            if let bandwidth = copy.bandwidth, bandwidth < 0 { copy.bandwidth = nil }
            if copy.phase == .downloading || copy.phase == .waiting { copy.phase = .failed; copy.message = "Tải native chưa hoàn tất khi app đóng; hãy tải lại." }
            let isNativePackage = copy.fileName.lowercased().hasSuffix(".movpkg")
            let package = root.appendingPathComponent(copy.fileName, isDirectory: true)
            if copy.phase == .finished && (!isNativePackage || !OfflinePlaybackSupport.validatePlayableFile(package)) {
                copy.phase = .unsupported
                copy.message = "Package AVFoundation không còn hợp lệ. Hãy xoá và tải lại."
            } else if copy.fileName.lowercased().hasSuffix(".m3u8") || copy.fileName.lowercased().hasSuffix(".ts") {
                copy.phase = .unsupported
                copy.message = "Tệp tải đời cũ không phải package AVFoundation. Hãy xoá và tải lại bằng native HLS."
            }
            return copy
        }
        save(force: true)
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
        return String(cleaned).prefix(100) + ".movpkg"
    }
}

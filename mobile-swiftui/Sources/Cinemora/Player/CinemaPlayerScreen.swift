import AVKit
import Combine
import SwiftUI
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var isLoading = false
    @Published var isSeeking = false
    @Published var playbackRate: Float = 1
    @Published var errorMessage: String?
    @Published var activeURL: URL?
    /// True once the current item has played to its end. The periodic time
    /// observer stops firing the moment playback ends, so without this flag the
    /// last published state stayed "playing" and the pause icon never went back
    /// to the play state.
    @Published var didReachEnd = false
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var activeRequestID = UUID()
    private var seekRequestID = UUID()
    /// Keep the user's play intent stable while AVPlayer is buffering or seeking.
    private var wantsToPlay = false
    private var suppressLoadingUntil = Date.distantPast
    private var overlayRecoveryTask: Task<Void, Never>?
    private var resumeAfterOverlay = false
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        notificationTokens = [
            NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recoverAfterAudioRouteChange() }
            },
            // Reach the end of the film or of the last episode: stop and hand
            // control back to the play/replay button.
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self,
                          let item = self.player.currentItem,
                          (note.object as? AVPlayerItem) === item else { return }
                    self.handleReachedEnd()
                }
            }
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            let requestID = MainActor.assumeIsolated { self?.activeRequestID }
            Task { @MainActor [weak self] in
                guard let self, let requestID, self.activeRequestID == requestID else { return }
                if time.seconds.isFinite, !self.isSeeking { self.currentTime = time.seconds }
                if let item = self.player.currentItem, item.duration.seconds.isFinite { self.duration = item.duration.seconds }
                switch self.player.timeControlStatus {
                case .playing:
                    self.isPlaying = self.wantsToPlay
                case .paused:
                    // A delayed observer callback must not erase a newer play
                    // or pause button action while AVPlayer changes status.
                    self.isPlaying = self.wantsToPlay
                case .waitingToPlayAtSpecifiedRate:
                    // Waiting is still playback from the controls' point of
                    // view; the loading indicator communicates the buffer wait.
                    self.isPlaying = self.wantsToPlay
                @unknown default:
                    break
                }
                if !self.isSeeking, Date() >= self.suppressLoadingUntil {
                    self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                }
            }
        }
    }

    /// Cheap stop for the moment the cover starts animating away. `shutdown()`
    /// tears the player item down and can block the main thread long enough to
    /// make the dismissal look sticky, so it is deferred until the animation is
    /// over.
    func pauseForDismissal() {
        wantsToPlay = false
        player.pause()
        isPlaying = false
        isLoading = false
    }
    func shutdown() {
        loadTask?.cancel()
        loadTask = nil
        overlayRecoveryTask?.cancel()
        overlayRecoveryTask = nil
        resumeAfterOverlay = false
        wantsToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        activeURL = nil
        isPlaying = false
        isLoading = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        itemObservation = nil
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        // `shutdown()` normally removes this, but the cover can be torn down
        // without it running. Leaving a periodic observer registered on a player
        // that outlives this controller is exactly the kind of thing that
        // eventually blows up while a screen is being dismissed.
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true, options: [])
    }
    private func recoverAfterAudioRouteChange() {
        guard activeURL != nil, wantsToPlay else { return }
        configureAudioSession()
        // Công tắc chuông/im lặng chỉ đổi audio route. Giữ nguyên item và
        // vị trí hiện tại, không replace/reload để tránh màn hình đen.
        player.play()
        wantsToPlay = true
        isPlaying = true
    }
    func load(_ episode: MovieEpisode, startAt: Double? = nil, localURL: URL? = nil, allowSubtitledPlaylist: Bool = true) {
        configureAudioSession()
        loadTask?.cancel()
        activeRequestID = UUID()
        let requestID = activeRequestID
        seekRequestID = UUID()
        isSeeking = false
        suppressLoadingUntil = .distantPast
        wantsToPlay = false
        player.pause()
        errorMessage = nil; currentTime = 0; duration = 0
        didReachEnd = false
        itemObservation = nil
        // Phụ đề rời: phát qua master playlist để PiP cũng hiện phụ đề.
        let subtitledURL = (localURL == nil && allowSubtitledPlaylist) ? episode.subtitledPlaylistURL : nil
        fallbackPlaybackURL = subtitledURL == nil ? nil : episode.playbackURL
        usedSubtitledPlaylist = subtitledURL != nil
        hasSidecarSubtitle = episode.subtitleURL != nil
        legibleGroup = nil
        legibleOption = nil
        nativeSubtitleActive = false
        guard let url = localURL ?? subtitledURL ?? episode.playbackURL else {
            player.pause(); player.replaceCurrentItem(with: nil); activeURL = nil
            isLoading = false
            errorMessage = "Tập này hiện chưa có đường dẫn phát."
            return
        }
        activeURL = url
        isLoading = true
        loadTask = Task { @MainActor in
            let item = await Self.makePlayerItem(videoURL: url, subtitleURL: episode.subtitleURL)
            guard !Task.isCancelled, self.activeRequestID == requestID else { return }
            item.preferredForwardBufferDuration = 8
            self.itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard self.activeRequestID == requestID else { return }
                    switch item.status {
                    case .readyToPlay:
                        // Phụ đề rời: giữ nhóm phụ đề cho PiP, còn khi xem bình
                        // thường app vẽ phụ đề theo thiết lập của người dùng.
                        if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
                           let option = group.options.first {
                            self.legibleGroup = group
                            self.legibleOption = option
                            if !self.hasSidecarSubtitle {
                                item.select(option, in: group)
                            }
                        }
                        self.loadTask?.cancel(); self.errorMessage = nil; self.isLoading = false
                        if let startAt, startAt > 0, startAt.isFinite {
                            let duration = item.duration.seconds
                            let safeStart = duration.isFinite && duration > 1 ? min(startAt, duration - 1) : startAt
                            self.seek(to: safeStart)
                        }
                    case .failed:
                        self.loadTask?.cancel()
                        // Master playlist phụ đề hỏng: quay về link M3U8 gốc ngay,
                        // người xem không phải bấm thử lại.
                        if self.usedSubtitledPlaylist, self.fallbackPlaybackURL != nil {
                            self.usedSubtitledPlaylist = false
                            self.fallbackPlaybackURL = nil
                            self.load(episode, startAt: startAt, localURL: nil, allowSubtitledPlaylist: false)
                            return
                        }
                        self.isLoading = false; self.activeURL = nil
                        self.errorMessage = item.error?.localizedDescription ?? "Nguồn HLS không phát được trên thiết bị này."
                    default: break
                    }
                }
            }
            self.player.replaceCurrentItem(with: item)
            self.wantsToPlay = true
            self.player.play()
            self.player.defaultRate = self.playbackRate
            self.player.rate = self.playbackRate
            self.isPlaying = true
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled, self.activeRequestID == requestID, self.isLoading else { return }
            self.isLoading = false
            self.errorMessage = "Nguồn phát phản hồi quá lâu. Hãy thử tập hoặc nguồn khác."
        }
    }

    /// Đang dùng phụ đề gốc của item (bật khi vào PiP) — lúc đó app ẩn lớp phụ đề tự vẽ.
    @Published private(set) var nativeSubtitleActive = false
    /// Nhóm phụ đề gốc của item (có khi link phát được bọc kèm phụ đề rời).
    private var legibleGroup: AVMediaSelectionGroup?
    private var legibleOption: AVMediaSelectionOption?
    /// Tập này có phụ đề rời do máy chủ/admin cung cấp hay không.
    private var hasSidecarSubtitle = false
    /// Đang phát qua master playlist phụ đề (để biết đường quay về link gốc).
    private var usedSubtitledPlaylist = false
    private var fallbackPlaybackURL: URL?

    /// PiP chỉ hiện phụ đề khi phụ đề thuộc media của AVPlayerItem, nên khi bật
    /// PiP thì chọn nhóm phụ đề gốc và tạm ẩn lớp phụ đề app tự vẽ; khi tắt PiP
    /// thì trả lại lớp phụ đề theo thiết lập của người dùng.
    func setNativeSubtitles(_ enabled: Bool) {
        guard hasSidecarSubtitle, let group = legibleGroup, let option = legibleOption else { return }
        if enabled {
            player.currentItem?.select(option, in: group)
            nativeSubtitleActive = true
        } else {
            player.currentItem?.select(nil, in: group)
            nativeSubtitleActive = false
        }
    }

    private static func makePlayerItem(videoURL: URL, subtitleURL: URL?) async -> AVPlayerItem {
        guard let subtitleURL else { return AVPlayerItem(url: videoURL) }
        return await withTaskGroup(of: AVPlayerItem.self) { group in
            group.addTask { await Self.makeComposedPlayerItem(videoURL: videoURL, subtitleURL: subtitleURL) }
            group.addTask {
                try? await Task.sleep(for: .seconds(1.5))
                return AVPlayerItem(url: videoURL)
            }
            let item = await group.next() ?? AVPlayerItem(url: videoURL)
            group.cancelAll()
            return item
        }
    }

    private static func makeComposedPlayerItem(videoURL: URL, subtitleURL: URL) async -> AVPlayerItem {
        do {
            let videoAsset = AVURLAsset(url: videoURL)
            let subtitleAsset = AVURLAsset(url: subtitleURL)
            let duration = try await videoAsset.load(.duration)
            let subtitleTracks = try await subtitleAsset.load(.tracks)
            guard duration.isNumeric, let subtitleTrack = subtitleTracks.first(where: { $0.mediaType == .text }) else {
                return AVPlayerItem(url: videoURL)
            }
            let composition = AVMutableComposition()
            try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoAsset, at: .zero)
            guard let track = composition.addMutableTrack(withMediaType: .text, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return AVPlayerItem(url: videoURL)
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: subtitleTrack, at: .zero)
            return AVPlayerItem(asset: composition)
        } catch {
            // HLS assets may not expose an external text track to a composition.
            // Keep the original AVPlayerItem so playback still works normally;
            // the existing SwiftUI subtitle controller remains the fallback.
            return AVPlayerItem(url: videoURL)
        }
    }

    func prepareForSystemOverlay() {
        guard activeURL != nil else { return }
        // Keep the current AVPlayerItem alive. iOS may keep audio/video
        // running under Control Center; rebuilding or seeking here causes
        // buffering and loses the exact viewing position.
        resumeAfterOverlay = isPlaying || player.timeControlStatus == .playing
    }
    func recoverAfterForeground() {
        guard resumeAfterOverlay, activeURL != nil else { return }
        // Resume the same item; never reload HLS or seek on this path.
        wantsToPlay = true
        player.play()
        isPlaying = true
        resumeAfterOverlay = false
    }
    private func handleReachedEnd() {
        wantsToPlay = false
        player.pause()
        isPlaying = false
        isLoading = false
        isSeeking = false
        if duration.isFinite, duration > 0 { currentTime = duration }
        didReachEnd = true
    }

    func togglePlayback() {
        if wantsToPlay || player.timeControlStatus == .playing {
            wantsToPlay = false
            player.pause()
            isPlaying = false
            return
        }
        // Pressing play on a finished item starts it over instead of doing nothing.
        if didReachEnd {
            didReachEnd = false
            wantsToPlay = true
            seek(to: 0)
            player.play()
            isPlaying = true
            return
        }
        wantsToPlay = true
        player.play()
        isPlaying = true
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        isPlaying = false
    }

    func toggleMute() {
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    func setVolume(_ value: Double) {
        player.volume = Float(min(1, max(0, value)))
    }

    func setPlaybackRate(_ value: Float) {
        playbackRate = value
        player.defaultRate = value
        if player.timeControlStatus == .playing { player.rate = value }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let target = max(0, duration.isFinite && duration > 0 ? min(seconds, duration) : seconds)
        seekRequestID = UUID()
        let requestID = seekRequestID
        didReachEnd = false
        isSeeking = true
        isLoading = false
        suppressLoadingUntil = Date().addingTimeInterval(1.2)
        currentTime = target
        // A new button press or scrub release supersedes the previous request.
        // Cancelling first prevents AVPlayer from walking through every queued
        // target, which is the main source of seek stutter on HLS streams.
        player.cancelPendingSeeks()
        let seekTime = CMTime(seconds: target, preferredTimescale: 600)
        let seekTolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: seekTolerance, toleranceAfter: seekTolerance) { [weak self] finished in
            guard let self else { return }
            Task { @MainActor in
                guard self.seekRequestID == requestID else { return }
                if finished {
                    let actual = self.player.currentTime().seconds
                    if actual.isFinite { self.currentTime = actual }
                }
                self.isSeeking = false
                self.isLoading = false
                if self.wantsToPlay {
                    // Some items remain paused after a cancelled/replaced seek;
                    // restore the user's intent without changing a deliberate
                    // pause that happened while the seek was in flight.
                    if self.player.timeControlStatus != .playing { self.player.play() }
                    self.isPlaying = true
                } else {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }
}

struct SubtitleCue: Identifiable, Equatable {
    let id = UUID()
    let start: Double
    let end: Double
    let text: String
}
@MainActor
final class SubtitleController: ObservableObject {
    @Published private(set) var currentText: String?
    /// Số câu đã nạp được, để màn cài đặt cho biết phụ đề có vào hay không.
    @Published private(set) var cueCount = 0
    /// Link phụ đề tải không được (nếu có) — hiện thẳng cho người xem biết.
    @Published private(set) var failedURL: String?
    @Published private(set) var availableTracks: [MovieEpisodeSubtitleTrack] = []
    @Published private(set) var selectedTrackID: String?
    private var cues: [SubtitleCue] = []
    private var bilingualCues: [SubtitleCue] = []
    private var loadTask: Task<Void, Never>?

    /// Nạp danh sách subtitle của tập. Đổi ngôn ngữ chỉ tải lại file VTT và giữ
    /// nguyên AVPlayerItem/vị trí phát nên không bị giật hoặc mất buffer video.
    func load(tracks: [MovieEpisodeSubtitleTrack]) {
        var unique: [MovieEpisodeSubtitleTrack] = []
        var seen = Set<String>()
        for track in tracks where !track.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if seen.insert(track.id).inserted { unique.append(track) }
        }
        availableTracks = unique
        selectedTrackID = unique.first?.id
        loadSelectedTrack()
    }

    func selectTrack(id: String) {
        guard availableTracks.contains(where: { $0.id == id }), selectedTrackID != id else { return }
        selectedTrackID = id
        loadSelectedTrack()
    }

    private func loadSelectedTrack() {
        loadTask?.cancel()
        cues = []; bilingualCues = []; currentText = nil
        cueCount = 0; failedURL = nil
        guard let id = selectedTrackID, let track = availableTracks.first(where: { $0.id == id }), let url = track.subtitleURL else { return }
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let text = await Self.fetchText(url), !Task.isCancelled else {
                if !Task.isCancelled { self.failedURL = url.absoluteString }
                return
            }
            let parsed = Self.parse(text)
            guard !Task.isCancelled else { return }
            self.cues = parsed
            self.cueCount = parsed.count
            if parsed.isEmpty { self.failedURL = url.absoluteString }
        }
    }

    func load(url: URL?, bilingualURL: URL? = nil) {
        loadTask?.cancel(); cues = []; bilingualCues = []; currentText = nil
        cueCount = 0; failedURL = nil
        availableTracks = []; selectedTrackID = nil
        guard url != nil || bilingualURL != nil else { return }
        loadTask = Task { @MainActor [weak self] in
            // The TV API may expose the same uploaded file at both the
            // episode and quality subtitle fields. Do not load it twice as
            // primary + bilingual, otherwise one subtitle appears twice.
            let distinctBilingualURL = bilingualURL == url ? nil : bilingualURL
            async let primaryText = Self.fetchText(url)
            async let secondaryText = Self.fetchText(distinctBilingualURL)
            guard !Task.isCancelled, let self else { return }
            let primary = await primaryText
            let secondary = await secondaryText
            if let text = primary { self.cues = Self.parse(text) }
            if let text = secondary,
               Self.normalizedTrack(text) != Self.normalizedTrack(primary ?? "") {
                self.bilingualCues = Self.parse(text)
            }
            self.cueCount = self.cues.count + self.bilingualCues.count
            // Có link nhưng không đọc được câu nào: báo để người xem biết là link
            // hỏng/chặn chứ không phải app im lặng.
            if self.cueCount == 0, let url { self.failedURL = url.absoluteString }
        }
    }
    private static func fetchText(_ url: URL?) async -> String? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        // Vài CDN phim chặn client lạ; gửi header giống trình duyệt để chắc chắn tải được.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/vtt,text/plain,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        } catch { return nil }
    }
    func update(time: Double, bilingual: Bool) {
        guard time.isFinite else { return }
        let primary = cues.last(where: { time >= $0.start && time < $0.end })
        let secondary = bilingual ? bilingualCues.last(where: { time >= $0.start && time < $0.end }) : nil
        var seen = Set<String>()
        let lines = [primary?.text, secondary?.text].compactMap { $0 }.filter { text in
            let key = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return seen.insert(key).inserted
        }
        let combined = lines.joined(separator: "\n")
        currentText = combined.isEmpty ? nil : combined
    }
    private static func normalizedTrack(_ source: String) -> String {
        source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Phân tích phụ đề WebVTT/SRT thành các câu có mốc thời gian.
    ///
    /// Bản cũ bắt buộc mốc thời gian phải **đủ 3 phần** `HH:MM:SS.mmm`. WebVTT lại cho
    /// phép `MM:SS.mmm` và rất nhiều nguồn phim phát đúng dạng đó, nên file tải về thành
    /// công nhưng bị bỏ sạch: không dòng phụ đề nào hiện. Phần này đọc được cả
    /// `HH:MM:SS.mmm`, `MM:SS.mmm`, `SS.mmm`, nhận dấu `,` của SRT, không cần dòng trống
    /// giữa các câu và tự bỏ thẻ định dạng.
    private static func parse(_ source: String) -> [SubtitleCue] {
        let normalized = source
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        var start: Double?
        var end: Double?
        var text: [String] = []
        func flush() {
            defer { start = nil; end = nil; text = [] }
            guard let start, let end, !text.isEmpty, end > start else { return }
            let joined = text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else { return }
            cues.append(SubtitleCue(start: start, end: end, text: joined))
        }
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flush()
                continue
            }
            if trimmed.contains("-->") {
                flush()
                let parts = trimmed.components(separatedBy: "-->")
                let right = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let rightParts = right.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                start = parseTime(parts[0])
                end = parseTime(rightParts.first.map(String.init) ?? "")
                // Một số file đặt luôn nội dung trên cùng dòng với mốc thời gian.
                if start != nil, end != nil, rightParts.count > 1 {
                    text = [stripTags(String(rightParts[1]))]
                }
                continue
            }
            // Trước mốc thời gian đầu tiên là phần đầu file: WEBVTT, số thứ tự, ghi chú.
            if start == nil, end == nil { continue }
            text.append(stripTags(trimmed))
        }
        flush()
        return cues.sorted { $0.start < $1.start }
    }
    /// Mốc thời gian phụ đề: `HH:MM:SS.mmm`, `MM:SS.mmm` hoặc `SS.mmm` (dấu `,` của SRT cũng nhận).
    private static func parseTime(_ raw: String) -> Double? {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: ";", with: ".")
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        let numbers = parts.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !numbers.contains(where: { $0 == nil }) else { return nil }
        let values = numbers.compactMap { $0 }
        switch values.count {
        case 3: return values[0] * 3600 + values[1] * 60 + values[2]
        case 2: return values[0] * 60 + values[1]
        default: return values[0]
        }
    }
    /// Bỏ thẻ định dạng (`<i>`, `{\\an8}`…) để chữ hiện sạch.
    private static func stripTags(_ line: String) -> String {
        var out = ""
        var inTag = false
        for character in line {
            if character == "<" { inTag = true; continue }
            if character == ">" { inTag = false; continue }
            if !inTag { out.append(character) }
        }
        while let open = out.firstIndex(of: "{"), let close = out[open...].firstIndex(of: "}") {
            out.removeSubrange(open...close)
        }
        return out
    }
}

final class PictureInPictureCoordinator: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var isSupported = false
    @Published private(set) var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            onActiveChanged?(isActive)
        }
    }
    /// Gọi khi PiP bật/tắt để trình phát đổi cách hiện phụ đề.
    var onActiveChanged: ((Bool) -> Void)?
    private var controller: AVPictureInPictureController?
    /// Watches `isPictureInPicturePossible`. Pressing the PiP button almost
    /// always happens before the layer has rendered a frame, and the flag stays
    /// false until it has — the old code retried once after 280ms and then gave
    /// up silently, which is why the button often did nothing at all.
    private var possibleObservation: NSKeyValueObservation?
    private var pendingStart = false
    /// Whether iOS may move playback into Picture in Picture by itself when the
    /// app leaves the foreground. Comes from the playback setting, so the
    /// setting now actually controls the behaviour instead of only hiding the
    /// button.
    private var autoStart = true

    @MainActor
    func setAutoStart(_ value: Bool) {
        autoStart = value
        controller?.canStartPictureInPictureAutomaticallyFromInline = value
    }

    @MainActor
    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if controller?.playerLayer !== layer {
            guard let next = AVPictureInPictureController(playerLayer: layer) else { return }
            next.delegate = self
            next.canStartPictureInPictureAutomaticallyFromInline = autoStart
            possibleObservation = next.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] controller, _ in
                Task { @MainActor in
                    guard let self, self.pendingStart, controller.isPictureInPicturePossible else { return }
                    self.pendingStart = false
                    controller.startPictureInPicture()
                }
            }
            controller = next
        }
        isSupported = controller != nil
    }

    @MainActor
    func start() {
        guard let controller else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            // Started as soon as the layer reports that the hand-off is allowed.
            pendingStart = true
        }
    }

    @MainActor
    func stop() {
        pendingStart = false
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.pendingStart = false; self?.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.pendingStart = false; self?.isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in self?.pendingStart = false; self?.isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

@MainActor
struct CinemaPlayerScreen: View {
    let movie: Movie
    let servers: [MovieServer]
    let initialServer: Int
    let initialEpisode: Int
    let resumeTime: Double?
    let subtitleCustomizationEnabled: Bool
    let onOpenRelated: ((Movie) -> Void)?
    @Environment(CinemaStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = PlaybackController()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @StateObject private var subtitles = SubtitleController()
    /// Âm lượng của máy, không phải âm lượng riêng của AVPlayer.
    @ObservedObject private var systemVolume = SystemVolume.shared
    @State private var subtitlePreferences = SubtitlePreferences()
    @State private var serverIndex = 0
    @State private var episodeIndex = 0
    @State private var controlsVisible = true
    @State private var picker: PickerKind?
    @State private var quickMenu: QuickMenu?
    @State private var volume = 1.0
    @State private var volumePopoverOpen = false
    @State private var adjustmentKind: AdjustmentKind?
    @State private var adjustmentValue = 0.0
    @State private var gestureStartValue = 0.0
    @State private var isAdjustmentGestureActive = false
    @State private var adjustmentHideTask: Task<Void, Never>?
    @State private var adjustmentPulse = false
    @State private var controlsLocked = false
    @State private var lockIndicatorVisible = true
    @State private var settingsOpen = false
    @State private var settingsTab: SettingsTab = .subtitle
    /// Chất lượng đang chọn cho tập hiện tại (phim thủ công có thể có 1080p / 2K / 4K).
    @State private var qualityIndex = 0
    /// Vị trí cần nạp lại sau khi đổi chất lượng.
    @State private var pendingResumeTime: Double?
    @State private var stopTimer: StopTimer = .off
    @State private var stopAtEpisodeEnabled = false
    @State private var stopAtEpisodeID: String?
    @State private var autoAdvanceEpisodes = true
    @State private var pictureInPictureEnabled = true
    @State private var relatedRecommendationsVisible = false
    @State private var selectedRelatedMovie: Movie?
    /// True while this player is being swapped for a related film. The cover
    /// stays presented in that case, so the landscape orientation must survive
    /// the swap — restoring portrait here made the next player rotate twice and
    /// show a black surface in between.
    @State private var handingOffToRelated = false
    /// Guards the deferred teardown: SwiftUI can call `onDisappear` more than
    /// once for a cover, and the teardown must only ever run once.
    @State private var didScheduleTeardown = false
    @State private var hasAppliedPlaybackDefaults = false
    @State private var didHandleEpisodeEnd = false
    @State private var videoFit: VideoFit = .fit
    @State private var isScrubbing = false
    @State private var scrubValue = 0.0
    @State private var hideTask: Task<Void, Never>?
    @State private var lockHideTask: Task<Void, Never>?
    @State private var stopTimerTask: Task<Void, Never>?
    @State private var stopTimerRemaining: Int?
    @State private var lastHistorySaveAt = Date.distantPast
    @State private var hasAppliedResumeTime = false

    private enum PickerKind { case episodes, sources }
    private enum AdjustmentKind: Equatable { case brightness, volume }
    private enum QuickMenu: Equatable { case videoFit, playbackRate }
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case audio = "Âm thanh"
        case subtitle = "Phụ đề"
        case display = "Hiển thị"
        case speed = "Tốc độ"
        case general = "Chung"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .audio: return "speaker.wave.2.fill"
            case .subtitle: return "captions.bubble.fill"
            case .display: return "textformat.size"
            case .speed: return "speedometer"
            case .general: return "slider.horizontal.3"
            }
        }
    }
    private enum StopTimer: String, CaseIterable, Identifiable {
        case off = "Tắt"
        case fifteen = "15 phút"
        case thirty = "30 phút"
        case sixty = "60 phút"
        case endOfEpisode = "Hết tập hiện tại"
        var id: String { rawValue }
        var seconds: Double? {
            switch self {
            case .off, .endOfEpisode: return nil
            case .fifteen: return 15 * 60
            case .thirty: return 30 * 60
            case .sixty: return 60 * 60
            }
        }
    }
    fileprivate enum VideoFit: String, CaseIterable { case fit = "Vừa", fill = "Đầy", cover = "Phủ" }
    private var server: MovieServer? { servers.indices.contains(serverIndex) ? servers[serverIndex] : nil }
    private var episodes: [MovieEpisode] { server?.episodes ?? [] }
    private var episode: MovieEpisode? { episodes.indices.contains(episodeIndex) ? episodes[episodeIndex] : nil }
    private var relatedMovies: [Movie] {
        var seen = Set<String>()
        return (store.homeMovies + store.homeSections.flatMap(\.movies)).filter { candidate in
            candidate.id != movie.id && seen.insert(candidate.id).inserted
        }.prefix(18).map { $0 }
    }
    private var selectableStopEpisodes: [MovieEpisode] {
        // Do not deduplicate by slug here. Some providers reuse/omit slugs
        // across sources; SwiftUI would then render only one row.
        return servers.flatMap(\.episodes)
    }

    private func stopEpisodeKey(_ episode: MovieEpisode) -> String {
        let value = episode.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value.isEmpty ? episode.name : value)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    init(movie: Movie, servers: [MovieServer], initialServer: Int, initialEpisode: Int, resumeTime: Double? = nil, subtitleCustomizationEnabled: Bool = false, onOpenRelated: ((Movie) -> Void)? = nil) {
        self.movie = movie
        self.servers = servers
        self.initialServer = initialServer
        self.initialEpisode = initialEpisode
        self.resumeTime = resumeTime
        self.subtitleCustomizationEnabled = subtitleCustomizationEnabled
        self.onOpenRelated = onOpenRelated
        let server = servers.indices.contains(initialServer) ? initialServer : 0
        let episodes = servers.indices.contains(server) ? servers[server].episodes : []
        _serverIndex = State(initialValue: server)
        _episodeIndex = State(initialValue: episodes.indices.contains(initialEpisode) ? initialEpisode : 0)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                // Không đặt neo MPVolumeView ở đây nữa: khung nhỏ không cắt được nội
                // dung bên trong nên thanh âm lượng hệ thống lộ ra ngoài giao diện.
                // MPVolumeView ẩn được gắn một lần trong cửa sổ ở gốc app.
                if playback.activeURL != nil {
                    NativeVideoSurface(player: playback.player, fit: videoFit, pipCoordinator: pipCoordinator).ignoresSafeArea().accessibilityLabel("Đang phát \(movie.name)")
                    subtitleOverlay(bottomInset: proxy.safeAreaInsets.bottom)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { if controlsLocked { controlsLocked = false; controlsVisible = true } else { toggleControls() } }
                } else {
                    PosterArt(url: movie.backdropURL, fallbackURL: movie.posterURL).ignoresSafeArea().overlay(Color.black.opacity(0.4))
                }

                if playback.activeURL != nil {
                    VStack {
                        HStack {
                            Spacer()
                            cinemoraWatermark
                        }
                        Spacer()
                    }
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 8))
                    .padding(.trailing, max(18, proxy.safeAreaInsets.trailing + 8))
                    .allowsHitTesting(false)
                }

                if controlsVisible && !controlsLocked {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        if playback.isLoading && !playback.isSeeking {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Đang tải nguồn phát…")
                                    .font(.auroraBody(12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .auroraSmoke(in: Capsule(), strength: 0.6)
                        }
                        if let error = playback.errorMessage {
                            errorCard(error)
                        } else if episode?.playbackURL == nil {
                            errorCard("Tập này chưa có nguồn phát khả dụng.")
                        }
                        Spacer()
                        centerControls
                        Spacer()
                        bottomControls
                    }
                    .padding(.horizontal, max(22, proxy.safeAreaInsets.leading + 16))
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 8))
                    .padding(.bottom, max(17, proxy.safeAreaInsets.bottom + 8))
                    .background(LinearGradient(colors: [.black.opacity(0.52), .clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                    .transition(.opacity)
                }

                if let picker { pickerOverlay(picker).transition(.opacity.combined(with: .scale(scale: 0.97))) }
                if let adjustmentKind {
                    adjustmentHUD(for: adjustmentKind)
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        .zIndex(9)
                }
                if controlsLocked {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { showLockIndicator() }
                    VStack {
                        HStack {
                            Spacer()
                            if lockIndicatorVisible {
                                Button { unlockControls() } label: {
                                    Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(width: 48, height: 48).background(.black.opacity(0.72), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Mở khóa điều khiển")
                                .transition(.opacity)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 8))
                    .padding(.trailing, max(18, proxy.safeAreaInsets.trailing + 8))
                }
                if relatedRecommendationsVisible {
                    relatedRecommendationsOverlay
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(12)
                }
                if settingsOpen {
                    settingsOverlay
                        .transition(.asymmetric(insertion: .scale(scale: 0.82, anchor: .topTrailing).combined(with: .opacity), removal: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity)))
                        .zIndex(13)
                }
                if !connectivity.isConnected {
                    NetworkUnavailableOverlay()
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        guard connectivity.isConnected else { return }
                        handleAdjustmentDrag(value, width: proxy.size.width, height: proxy.size.height)
                    }
                    .onEnded { _ in
                        guard connectivity.isConnected else { return }
                        finishAdjustmentGesture()
                    }
            )
            .animation(Motion.sheet, value: picker != nil)
            .animation(.easeInOut(duration: 0.22), value: controlsVisible)
            .animation(Motion.sheet, value: settingsOpen)
            .onChange(of: episodeIndex) { _, _ in loadCurrentEpisode() }
            .onChange(of: serverIndex) { _, _ in
                if episodeIndex != 0 { episodeIndex = 0 }
                else { loadCurrentEpisode() }
            }
            .onChange(of: systemVolume.value) { _, value in
                // Người dùng bấm nút cứng bên hông máy thì thanh trượt trong app khớp theo.
                if volume != value { volume = value }
            }
            .onChange(of: playback.isPlaying) { _, isPlaying in if isPlaying { scheduleHide() } }
            .onChange(of: playback.isLoading) { _, isLoading in handleLoadingChange(isLoading) }
            .onChange(of: playback.errorMessage) { _, _ in handlePlaybackErrorChange() }
            .onChange(of: playback.currentTime) { _, time in
                subtitles.update(time: time, bilingual: false)
                handlePlaybackProgress()
            }
            .onChange(of: subtitlePreferences) { _, value in handleSubtitlePreferencesChange(value) }
            .onChange(of: stopTimer) { _, _ in scheduleStopTimer() }
            .onChange(of: stopAtEpisodeEnabled) { _, enabled in handleStopAtEpisodeToggle(enabled) }
            .onChange(of: stopAtEpisodeID) { _, _ in scheduleStopTimer() }
            .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
            .onAppear {
                applyPlaybackDefaults()
                loadCurrentEpisode()
                scheduleHide()
                // Thanh trượt phản ánh đúng mức âm lượng đang có của máy.
                volume = systemVolume.value
            }
            .task {
                await store.loadHome()
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                forceLandscape()
            }
            .task(id: store.accountUser?.id) {
                guard store.accountUser != nil else { return }
                await store.synchronizeSubtitlePreferencesForCurrentAccount()
                guard !Task.isCancelled else { return }
                subtitlePreferences = store.playbackDefaults.subtitlePreferences
            }
            .onDisappear { handlePlayerDisappear() }
            .statusBarHidden(true)
        }
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(item: $selectedRelatedMovie, onDismiss: {
            // Khi đóng trang chi tiết phim liên quan, thoát luôn player A.
            dismiss()
        }) { related in
            MovieDetailScreen(
                slug: related.slug,
                autoPlayOnLoad: true,
                onExitRelated: { selectedRelatedMovie = nil },
                offlineGuardEnabled: true
            )
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }

    private var topBar: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack(spacing: 9) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(.white)
                .auroraSmoke(strength: 0.4)
                .accessibilityLabel("Trở lại")

                VStack(alignment: .leading, spacing: 3) {
                    Text(movie.name).font(.auroraLabel(12, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text("\(episode?.name ?? "Chọn tập")  ·  \(server?.name ?? "Nguồn")")
                        .font(.auroraBody(9))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .auroraSmoke(in: Capsule(), strength: 0.4)

                Spacer(minLength: 8)

                Button { withAnimation(Motion.sheet) { picker = .episodes }; controlsVisible = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(.white)
                .auroraSmoke(strength: 0.4)
                .accessibilityLabel("Danh sách tập")

                if servers.count > 1 {
                    Button { withAnimation(Motion.sheet) { picker = .sources }; controlsVisible = true } label: {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                    }
                    .buttonStyle(.auroraPress(scale: 0.9))
                    .foregroundStyle(.white)
                    .auroraSmoke(strength: 0.4)
                    .accessibilityLabel("Chọn nguồn phát")
                }

                if pictureInPictureEnabled && movie.allowPip != false && pipCoordinator.isSupported {
                    Button {
                        pipCoordinator.isActive ? pipCoordinator.stop() : pipCoordinator.start()
                        scheduleHide()
                    } label: {
                        Image(systemName: pipCoordinator.isActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                    }
                    .buttonStyle(.auroraPress(scale: 0.9))
                    .foregroundStyle(pipCoordinator.isActive ? Color.auroraVoid : .white)
                    .background {
                        Circle().fill(pipCoordinator.isActive ? AnyShapeStyle(LinearGradient.auroraPrimary) : AnyShapeStyle(Color.black.opacity(0.4)))
                    }
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8) }
                    .accessibilityLabel(pipCoordinator.isActive ? "Thoát Picture-in-Picture" : "Bật Picture-in-Picture")
                }

                Button {
                    withAnimation(Motion.sheet) { relatedRecommendationsVisible = true }
                    hideTask?.cancel()
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(.white)
                .auroraSmoke(strength: 0.4)
                .accessibilityLabel("Video liên quan")

                quickControl(icon: "rectangle.on.rectangle", title: "Tỷ lệ", value: videoFit.rawValue, menu: .videoFit)
                quickControl(icon: "speedometer", title: "Tốc độ", value: playbackRateLabel, menu: .playbackRate)

                Button {
                    withAnimation(Motion.sheet) {
                        if !visibleSettingsTabs.contains(settingsTab), let firstTab = visibleSettingsTabs.first {
                            settingsTab = firstTab
                        }
                        settingsOpen.toggle()
                        quickMenu = nil
                        volumePopoverOpen = false
                    }
                    if settingsOpen { hideTask?.cancel() } else { scheduleHide() }
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(settingsOpen ? Color.auroraVoid : .white)
                .background {
                    Circle().fill(settingsOpen ? AnyShapeStyle(LinearGradient.auroraPrimary) : AnyShapeStyle(Color.black.opacity(0.4)))
                }
                .overlay { Circle().strokeBorder(Color.white.opacity(settingsOpen ? 0.35 : 0.16), lineWidth: 0.8) }
                .accessibilityLabel("Cài đặt phát video")

                Button { lockControls() } label: {
                    Image(systemName: "lock").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(.white)
                .auroraSmoke(strength: 0.4)
                .accessibilityLabel("Khóa điều khiển")
            }
            if let quickMenu { quickMenuPanel(quickMenu) }
        }
    }

    private var cinemoraLogo: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles.tv.fill").font(.system(size: 13, weight: .black))
            Text("CINEMORA").font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.1)
        }
        .foregroundStyle(LinearGradient.auroraPrimary)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .auroraSmoke(in: Capsule(), strength: 0.4)
        .accessibilityLabel("Cinemora")
    }

    private var cinemoraWatermark: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles.tv.fill").font(.system(size: 12, weight: .black))
            Text("CINEMORA").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.34)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.3), radius: 6)
    }

    private var playbackRateLabel: String {
        playback.playbackRate == 1 ? "1x" : "\(formatRate(playback.playbackRate))x"
    }

    /// Tập hiện tại có phụ đề rời hay không (từ API hoặc nguồn admin thêm thủ công).
    ///
    /// Trước đây điều kiện này còn đòi `subtitleCustomizationEnabled` — cờ chỉ được
    /// bật ở màn Truyền Hình — nên phim lẻ/phim bộ tải phụ đề rời về nhưng không bao
    /// giờ hiện. Giờ chỉ cần tập có phụ đề là hiện.
    private var subtitleAvailable: Bool {
        guard let episode else { return false }
        let source = episode.withQuality(qualityIndex)
        return !source.availableSubtitleTracks.isEmpty || source.bilingualSubtitleURL != nil
    }
    private var hasCurrentSubtitle: Bool { subtitleAvailable }

    private var visibleSettingsTabs: [SettingsTab] {
        // Chỉ cho chỉnh phụ đề khi tập hiện tại thật sự có subtitle đã đăng.
        // Các tùy chọn phát còn lại nằm trong Advanced > Chung để không bị lặp.
        hasCurrentSubtitle ? [.subtitle, .general] : [.general]
    }

    private var effectiveSettingsTab: SettingsTab {
        visibleSettingsTabs.contains(settingsTab) ? settingsTab : .general
    }

    private func formatRate(_ rate: Float) -> String {
        String(format: "%g", rate)
    }

    private func quickControl(icon: String, title: String, value: String, menu: QuickMenu) -> some View {
        Button {
            withAnimation(Motion.sheet) {
                quickMenu = quickMenu == menu ? nil : menu
                settingsOpen = false
                volumePopoverOpen = false
            }
            controlsVisible = true
            hideTask?.cancel()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(value).font(.system(size: 9, weight: .black, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(quickMenu == menu ? Color.auroraVoid : .white)
            .frame(width: 54, height: 42)
            .background {
                if quickMenu == menu {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient.auroraPrimary)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.4))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(quickMenu == menu ? 0.35 : 0.16), lineWidth: 0.8)
            }
        }
        .buttonStyle(.auroraPress(scale: 0.92))
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder
    private func quickMenuPanel(_ menu: QuickMenu) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(menu == .videoFit ? "TỶ LỆ KHUNG HÌNH" : "TỐC ĐỘ PHÁT")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.auroraViolet)
                Spacer(minLength: 20)
                Button {
                    withAnimation(Motion.sheet) { quickMenu = nil }
                    scheduleHide()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng lựa chọn")
            }
            if menu == .videoFit {
                ForEach(VideoFit.allCases, id: \.self) { fit in
                    quickOption(title: fit.rawValue, detail: fit == .fit ? "Giữ nguyên khung hình" : fit == .fill ? "Lấp đầy màn hình" : "Phóng phủ toàn màn hình", selected: fit == videoFit) {
                        videoFit = fit
                    }
                }
            } else {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    quickOption(title: rate == 1 ? "Bình thường" : "\(formatRate(Float(rate)))x", detail: rate == 1 ? "Tốc độ mặc định" : "Điều chỉnh tốc độ phát", selected: playback.playbackRate == Float(rate)) {
                        playback.setPlaybackRate(Float(rate))
                    }
                }
            }
        }
        .padding(13)
        .frame(width: 266)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.auroraRaised.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
    }

    private func quickOption(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            withAnimation(Motion.sheet) { quickMenu = nil }
            scheduleHide()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.auroraViolet : .white.opacity(0.45))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.auroraLabel(12, weight: .bold)).foregroundStyle(.white)
                    Text(detail).font(.auroraBody(9)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(
                selected ? Color.auroraViolet.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(subtitlePreferences.font)
            .tracking(subtitlePreferences.letterSpacing)
            .lineSpacing(subtitlePreferences.lineSpacing)
            .foregroundStyle(subtitlePreferences.textColor)
            .multilineTextAlignment(subtitlePreferences.textAlignment)
            .padding(.horizontal, 24)
            .padding(.vertical, subtitlePreferences.backgroundEnabled ? 5 : 0)
            .background { if subtitlePreferences.backgroundEnabled { RoundedRectangle(cornerRadius: subtitlePreferences.cornerRadius).fill(subtitlePreferences.backgroundColor.opacity(subtitlePreferences.backgroundOpacity)) } }
            .frame(maxWidth: .infinity, alignment: subtitlePreferences.frameAlignment)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: subtitlePreferences.outlineWidth)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: -subtitlePreferences.outlineWidth)
    }

    private var settingsOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Motion.sheet) { settingsOpen = false }
                        scheduleHide()
                    }
                settingsPanel(width: min(410, max(300, proxy.size.width - 28)))
                    .padding(.top, max(14, proxy.safeAreaInsets.top + 8))
                    .padding(.trailing, max(14, proxy.safeAreaInsets.trailing + 10))
                    .padding(.bottom, max(14, proxy.safeAreaInsets.bottom + 8))
            }
        }
        .ignoresSafeArea()
    }

    private func settingsPanel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.auroraViolet)
                Text("Cài đặt").font(.auroraDisplay(17)).foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(Motion.sheet) { settingsOpen = false }
                    scheduleHide()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.08), in: Circle())
                .accessibilityLabel("Đóng cài đặt")
            }
            settingsTabs
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
            settingsTabContent
        }
        .padding(18)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.auroraRaised.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(0.55), radius: 30, x: -8, y: 14)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { }
    }

    private var settingsTabs: some View {
        HStack(spacing: 5) {
            ForEach(visibleSettingsTabs) { tab in
                Button {
                    withAnimation(Motion.gentle) { settingsTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .bold))
                        Text(tab.rawValue).font(.system(size: 8, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(effectiveSettingsTab == tab ? Color.auroraVoid : .white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        if effectiveSettingsTab == tab {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient.auroraPrimary)
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Cho biết phụ đề của tập đang xem đã nạp được hay chưa.
    @ViewBuilder
    private var subtitleStatusLine: some View {
        if let failed = subtitles.failedURL {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                Text("Không tải được phụ đề — kiểm tra lại link phụ đề")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(Color.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .accessibilityLabel("Không tải được phụ đề từ \(failed)")
        } else if subtitles.cueCount > 0 {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .bold))
                Text("Đã nạp \(subtitles.cueCount) câu phụ đề").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.auroraViolet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var subtitleLanguagePicker: some View {
        if subtitles.availableTracks.count > 1 {
            VStack(alignment: .leading, spacing: 7) {
                Text("NGÔN NGỮ PHỤ ĐỀ")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Color.auroraViolet)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], spacing: 6) {
                    ForEach(subtitles.availableTracks) { track in
                        Button {
                            subtitles.selectTrack(id: track.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: subtitles.selectedTrackID == track.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(track.language)
                                    .font(.auroraLabel(11, weight: .bold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(subtitles.selectedTrackID == track.id ? Color.auroraVoid : .white.opacity(0.78))
                            .padding(.horizontal, 9)
                            .frame(minHeight: 38)
                            .background(subtitles.selectedTrackID == track.id ? AnyShapeStyle(LinearGradient.auroraPrimary) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch effectiveSettingsTab {
        case .audio:
            settingsRow(icon: systemVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Âm lượng máy", detail: systemVolume.isMuted ? "Đang tắt tiếng" : "\(Int(systemVolume.value * 100))%") {
                HStack(spacing: 7) {
                    Slider(value: volumeBinding, in: 0...1).tint(Color.auroraViolet).frame(width: 130)
                    Button { systemVolume.toggleMute() } label: { Image(systemName: systemVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(Color.auroraViolet) }.buttonStyle(.plain)
                }
            }
        case .subtitle:
            if hasCurrentSubtitle {
                ScrollView(.vertical, showsIndicators: false) {
                    subtitleLanguagePicker
                    subtitleStatusLine
                    subtitlePreview
                    SubtitlePreferencesEditor(preferences: $subtitlePreferences, compact: true).padding(.vertical, 2)
                }
                .frame(minHeight: 245, maxHeight: 390, alignment: .top)
            }
        case .display:
            VStack(alignment: .leading, spacing: 10) {
                qualityPickerRow
                settingsRow(icon: "rectangle.on.rectangle", title: "Tỷ lệ khung hình", detail: videoFit.rawValue) {
                    Picker("Tỷ lệ khung hình", selection: $videoFit) {
                        ForEach(VideoFit.allCases, id: \.self) { fit in Text(fit.rawValue).tag(fit) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Toggle(isOn: $pictureInPictureEnabled) {
                    settingsLabel(icon: "pip.enter", title: "Picture-in-Picture", detail: "Cho phép phát nổi khi rời trình phát")
                }
                .tint(Color.auroraViolet)
                // The setting used to only hide the button. It now also decides
                // whether iOS may move playback into PiP by itself when the app
                // leaves the foreground.
                .onChange(of: pictureInPictureEnabled) { _, value in
                    pipCoordinator.setAutoStart(value && movie.allowPip != false)
                }
            }
        case .speed:
            VStack(alignment: .leading, spacing: 8) {
                settingsLabel(icon: "speedometer", title: "Tốc độ phát", detail: "Đang chọn \(playbackRateLabel)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button {
                            playback.setPlaybackRate(Float(rate))
                            scheduleHide()
                        } label: {
                            Text(rate == 1 ? "Bình thường" : "\(formatRate(Float(rate)))x")
                                .font(.auroraLabel(14, weight: .bold))
                                .foregroundStyle(playback.playbackRate == Float(rate) ? Color.auroraVoid : .white.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background {
                                    if playback.playbackRate == Float(rate) {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient.auroraPrimary)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .general:
            VStack(alignment: .leading, spacing: 10) {
                settingsRow(icon: "moon.zzz.fill", title: "Tự dừng phát", detail: "Dừng sau một khoảng thời gian") {
                    Picker("Tự dừng phát", selection: $stopTimer) {
                        ForEach(StopTimer.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Color.auroraViolet)
                }
                if let stopTimerRemaining {
                    HStack(spacing: 7) {
                        Image(systemName: "timer").foregroundStyle(Color.auroraViolet)
                        Text("Tự dừng sau \(formatCountdown(stopTimerRemaining))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
                Toggle(isOn: $stopAtEpisodeEnabled) {
                    settingsLabel(icon: "stop.circle.fill", title: "Dừng ở tập đã chọn", detail: "Tự chuyển đến tập mục tiêu rồi dừng")
                }
                .tint(Color.auroraViolet)
                if stopAtEpisodeEnabled { episodeStopSelector }
                Toggle(isOn: $autoAdvanceEpisodes) {
                    settingsLabel(icon: "forward.end.fill", title: "Tự động chuyển tập", detail: "Phát tập kế tiếp khi tập hiện tại kết thúc")
                }
                .tint(Color.auroraViolet)
            }
        }
    }

    private var subtitlePreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color.auroraSky.opacity(0.38), .black.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 96)
                Text("Đây là phụ đề xem trước")
                    .font(subtitlePreferences.font)
                    .tracking(subtitlePreferences.letterSpacing)
                    .lineSpacing(subtitlePreferences.lineSpacing)
                    .foregroundStyle(subtitlePreferences.textColor)
                    .multilineTextAlignment(subtitlePreferences.textAlignment)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: subtitlePreferences.frameAlignment)
                    // Preview dùng tỷ lệ thu nhỏ, nhưng luôn di chuyển cùng
                    // chiều với subtitle thật khi đổi khoảng cách phía dưới.
                    .padding(.bottom, min(max(subtitlePreferences.bottomSpacing * 0.55, 4), 72))
                    .padding(.vertical, subtitlePreferences.backgroundEnabled ? 5 : 0)
                    .background { if subtitlePreferences.backgroundEnabled { RoundedRectangle(cornerRadius: subtitlePreferences.cornerRadius).fill(subtitlePreferences.backgroundColor.opacity(subtitlePreferences.backgroundOpacity)) } }
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: subtitlePreferences.outlineWidth)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: -subtitlePreferences.outlineWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func settingsEmpty(icon: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.auroraViolet)
            Text(text).font(.auroraBody(10)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    private var episodeStopSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHỌN TẬP DỪNG")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 4)
            if selectableStopEpisodes.isEmpty {
                Text("API chưa trả về danh sách tập cho phim này. Hãy đóng trình phát và mở lại phim để tải dữ liệu mới.")
                    .font(.auroraBody(9))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(selectableStopEpisodes.enumerated()), id: \.element.id) { index, item in
                            Button {
                                stopAtEpisodeID = stopEpisodeKey(item)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: stopAtEpisodeID == stopEpisodeKey(item) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(stopAtEpisodeID == stopEpisodeKey(item) ? Color.auroraViolet : .white.opacity(0.42))
                                    Text(item.name).font(.auroraLabel(10, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 9)
                                .frame(minHeight: 34)
                                .background(
                                    stopAtEpisodeID == stopEpisodeKey(item) ? Color.auroraViolet.opacity(0.18) : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // `maxHeight` alone lets SwiftUI collapse this ScrollView to zero
                // height inside the settings VStack. Keep one row visible and
                // cap long episode lists so they remain scrollable.
                .frame(minHeight: 39, maxHeight: 142)
                .scrollClipDisabled()
            }
        }
        .padding(.leading, 32)
    }

    private func settingsRow<Content: View>(icon: String, title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            settingsLabel(icon: icon, title: title, detail: detail)
            Spacer(minLength: 4)
            content()
        }
    }

    private func settingsLabel(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.auroraViolet).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.auroraLabel(11, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.auroraBody(8)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 38) {
            Button {
                playback.seek(to: max(0, playback.currentTime - 10))
                scheduleHide()
            } label: {
                skipControl("gobackward.10")
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .accessibilityLabel("Lùi 10 giây")

            Button {
                playback.togglePlayback()
                scheduleHide()
            } label: {
                // At the end of the film the button becomes "replay" instead of
                // staying on the pause glyph.
                Image(systemName: playback.isPlaying ? "pause.fill" : (playback.didReachEnd ? "arrow.counterclockwise" : "play.fill"))
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Color.auroraVoid)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(LinearGradient.auroraPrimary))
                    .auroraHalo(.auroraViolet, radius: 26, opacity: 0.55)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .accessibilityLabel(playback.isPlaying ? "Tạm dừng" : "Phát")

            Button {
                playback.seek(to: min(playback.duration, playback.currentTime + 10))
                scheduleHide()
            } label: {
                skipControl("goforward.10")
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .accessibilityLabel("Tiến 10 giây")
        }
    }

    private func skipControl(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .auroraSmoke(strength: 0.5)
    }

    private func adjustmentHUD(for kind: AdjustmentKind) -> some View {
        VStack(spacing: 9) {
            Image(systemName: kind == .brightness ? "sun.max.fill" : (playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.auroraVoid)
                .frame(width: 34, height: 34)
                .background(Circle().fill(LinearGradient.auroraPrimary))
                .scaleEffect(adjustmentPulse ? 1.12 : 1)
            GeometryReader { proxy in
                let fillHeight = max(8, proxy.size.height * adjustmentValue)
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.18)).frame(width: 7)
                    Capsule().fill(LinearGradient.auroraPrimary).frame(width: 7, height: fillHeight)
                    Circle().fill(Color.auroraViolet).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: Color.auroraViolet.opacity(0.6), radius: 10)
                        .offset(y: -(fillHeight - 10))
                }
            }
            .frame(width: 26, height: 100)
            Text("\(Int(adjustmentValue * 100))%")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        }
        .frame(width: 66, height: 174)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: kind == .brightness ? .bottomLeading : .bottomTrailing)
        .padding(.horizontal, 34)
        .padding(.bottom, 86)
        .allowsHitTesting(false)
        .onAppear {
            adjustmentPulse = false
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { adjustmentPulse = true }
        }
    }

    /// Thanh trượt đọc/ghi trực tiếp âm lượng của máy.
    private var volumeBinding: Binding<Double> {
        Binding(get: { systemVolume.value }, set: { systemVolume.set($0) })
    }

    private func handleAdjustmentDrag(_ value: DragGesture.Value, width: CGFloat, height: CGFloat) {
        guard !controlsLocked, picker == nil, !settingsOpen, !relatedRecommendationsVisible else { return }
        guard value.startLocation.y > height * 0.22 else { return }
        if !isAdjustmentGestureActive {
            guard abs(value.translation.height) > max(8, abs(value.translation.width) * 0.75) else { return }
            isAdjustmentGestureActive = true
            let isBrightness = value.startLocation.x < width / 2
            adjustmentKind = isBrightness ? .brightness : .volume
            gestureStartValue = isBrightness ? Double(UIScreen.main.brightness) : systemVolume.value
        }

        let nextValue = min(1, max(0, gestureStartValue - Double(value.translation.height / 340)))
        adjustmentValue = nextValue
        if adjustmentKind == .brightness {
            UIScreen.main.brightness = CGFloat(nextValue)
        } else {
            volume = nextValue
            systemVolume.set(nextValue)
        }
        withAnimation(.easeOut(duration: 0.14)) { adjustmentPulse.toggle() }
        scheduleAdjustmentHUDHide()
    }

    private func finishAdjustmentGesture() {
        guard isAdjustmentGestureActive else { return }
        isAdjustmentGestureActive = false
        scheduleAdjustmentHUDHide()
    }

    private func scheduleAdjustmentHUDHide() {
        adjustmentHideTask?.cancel()
        adjustmentHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { adjustmentKind = nil }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(formatTime(isScrubbing ? scrubValue : playback.currentTime))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 44, alignment: .leading)
                Slider(value: Binding(get: { isScrubbing ? scrubValue : playback.currentTime }, set: { value in
                    // SwiftUI may write the binding during ordinary view
                    // updates; those writes must not start a scrub implicitly.
                    guard isScrubbing else { return }
                    scrubValue = value
                }), in: 0...max(1, playback.duration), onEditingChanged: { editing in
                    if editing {
                        scrubValue = playback.currentTime
                        isScrubbing = true
                    } else if isScrubbing {
                        let target = scrubValue
                        isScrubbing = false
                        playback.seek(to: target)
                        scheduleHide()
                    }
                })
                    .tint(Color.auroraViolet)
                Text(formatTime(playback.duration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 44, alignment: .trailing)
                Button {
                    withAnimation(Motion.sheet) { volumePopoverOpen.toggle() }
                    scheduleHide()
                } label: {
                    Image(systemName: systemVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .auroraSmoke(strength: 0.5)
                .accessibilityLabel("Điều chỉnh âm lượng")
            }
            .overlay(alignment: .bottomTrailing) {
                if volumePopoverOpen {
                    HStack(spacing: 10) {
                        Button { systemVolume.toggleMute() } label: {
                            Image(systemName: systemVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(systemVolume.isMuted ? "Bật âm thanh" : "Tắt âm thanh")
                        Slider(value: volumeBinding, in: 0...1, onEditingChanged: { editing in if !editing { scheduleHide() } })
                            .tint(Color.auroraViolet)
                            .frame(width: 150)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(Color.auroraRaised.opacity(0.96))
                            .overlay(Capsule().strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9))
                            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    }
                    .offset(y: -52)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
                }
            }
            HStack {
                Text(movie.name).font(.auroraBody(9)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                Spacer()
                if let episode {
                    Text(episode.name).font(.auroraLabel(9, weight: .bold)).foregroundStyle(Color.auroraViolet).lineLimit(1)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.auroraViolet)
            Text("Không thể phát video").font(.auroraLabel(14, weight: .bold)).foregroundStyle(.white)
            Text(message)
                .font(.auroraBody(10))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button { dismiss() } label: {
                Text("Trở lại")
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(Color.auroraVoid)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(LinearGradient.auroraPrimary))
            }
            .buttonStyle(.auroraPress(scale: 0.94))
        }
        .padding(18)
        .frame(maxWidth: 340)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
        }
    }

    private var relatedRecommendationsOverlay: some View {
        ZStack {
            CinemaBackground()
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionEyebrow(text: "CINEMORA · FULLSCREEN BROWSING")
                        Text("Video liên quan")
                            .font(.auroraDisplay(25))
                            .foregroundStyle(.white)
                        Text("Khám phá thêm phim tương tự mà không cần rời trình phát")
                            .font(.auroraBody(11))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(Motion.sheet) { relatedRecommendationsVisible = false }
                        scheduleHide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
                    }
                    .buttonStyle(.auroraPress(scale: 0.9))
                    .accessibilityLabel("Đóng video liên quan")
                }

                if relatedMovies.isEmpty {
                    StateMessage(icon: "sparkles.tv", title: "Chưa có gợi ý", detail: "Hãy quay lại trang chủ để cập nhật danh sách phim.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 18) {
                            ForEach(Array(relatedMovies.enumerated()), id: \.element.id) { index, related in
                                Button {
                                    openRelatedMovie(related)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        PosterArt(url: related.posterURL, fallbackURL: related.backdropURL)
                                            .frame(height: 180)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.8)
                                            }
                                            .shadow(color: .black.opacity(0.4), radius: 14, y: 9)
                                        Text(related.name)
                                            .font(.auroraLabel(12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text(related.originName ?? "Phim đề xuất")
                                            .font(.auroraBody(9))
                                            .foregroundStyle(Color.auroraTextTertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.auroraPress(scale: 0.97))
                                .auroraReveal(index % 10)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func openRelatedMovie(_ related: Movie) {
        // Pause, do not release the item. This view stays on screen while the
        // related film loads — the cover swaps its content instead of closing —
        // and releasing the item here left a black surface covering the app
        // until the new playback appeared. `onDisappear` does the real teardown
        // once this player is actually gone.
        saveLocalWatchProgress()
        playback.pauseForDismissal()
        subtitles.load(url: nil)
        hideTask?.cancel()
        withAnimation(Motion.sheet) {
            relatedRecommendationsVisible = false
        }
        if let onOpenRelated {
            // MovieDetailScreen thay player A bằng trang phim B. B tự mở
            // player, nên khi đóng có thể trở về đúng trang chi tiết B.
            handingOffToRelated = true
            onOpenRelated(related)
            return
        }
        selectedRelatedMovie = related
    }

    private func pickerOverlay(_ kind: PickerKind) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture {
                withAnimation(Motion.sheet) { picker = nil }
                scheduleHide()
            }
            VStack(spacing: 15) {
                Capsule().fill(.white.opacity(0.34)).frame(width: 42, height: 4).padding(.top, 4)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionEyebrow(text: kind == .episodes ? "CINEMORA · TẬP PHIM" : "CINEMORA · CHẤT LƯỢNG")
                        Text(kind == .episodes ? "Danh sách tập" : "Chọn nguồn phát")
                            .font(.auroraDisplay(22))
                            .foregroundStyle(.white)
                        Text("Đang phát: \(kind == .episodes ? (episode?.name ?? "") : (server?.name ?? ""))")
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        withAnimation(Motion.sheet) { picker = nil }
                        scheduleHide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.auroraPress(scale: 0.9))
                    .accessibilityLabel("Đóng danh sách")
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 9)], spacing: 9) {
                        if kind == .episodes {
                            ForEach(Array(episodes.enumerated()), id: \.element.id) { index, item in
                                pickerRow(number: index + 1, title: item.name, selected: index == episodeIndex) {
                                    episodeIndex = index
                                    controlsVisible = true
                                }
                            }
                        } else {
                            ForEach(Array(servers.enumerated()), id: \.element.id) { index, item in
                                pickerRow(number: index + 1, title: item.name, selected: index == serverIndex) {
                                    serverIndex = index
                                    controlsVisible = true
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 340)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 840)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.auroraRaised.opacity(0.97))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                    }
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
            }
            .padding(.horizontal, 22)
        }
        .zIndex(10)
    }

    private func pickerRow(number: Int, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(selected ? Color.auroraVoid : Color.auroraViolet)
                Text(title)
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(selected ? Color.auroraVoid : .white.opacity(0.86))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.auroraVoid)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient.auroraPrimary)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.3 : 0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.auroraPress(scale: 0.96))
        .animation(Motion.gentle, value: selected)
    }

    private func loadCurrentEpisode() {
        guard let episode else { return }
        didHandleEpisodeEnd = false
        // Tập đang chọn có thể có nhiều chất lượng; lấy đúng chất lượng đang chọn.
        let qualities = episode.qualities ?? []
        if qualityIndex >= qualities.count { qualityIndex = 0 }
        let source = episode.withQuality(qualityIndex)
        let startAt = pendingResumeTime ?? (hasAppliedResumeTime ? nil : resumeTime)
        if !source.availableSubtitleTracks.isEmpty {
            subtitles.load(tracks: source.availableSubtitleTracks)
        } else {
            subtitles.load(url: source.subtitleURL, bilingualURL: source.bilingualSubtitleURL)
        }
        // Ưu tiên bản đã tải về máy để xem được khi mất mạng.
        let offlineURL = downloads.localURL(
            movieSlug: movie.slug,
            episodeSlug: source.slug.isEmpty ? source.name : source.slug
        )
        playback.load(source, startAt: startAt, localURL: offlineURL)
        if startAt != nil { hasAppliedResumeTime = true }
        pendingResumeTime = nil
        saveLocalWatchProgress()
    }

    /// Đổi chất lượng: nạp lại đúng vị trí đang xem bằng link của chất lượng mới.
    private func selectQuality(_ index: Int) {
        guard index != qualityIndex else { return }
        let position = playback.currentTime
        if position > 1 { pendingResumeTime = position }
        qualityIndex = index
        loadCurrentEpisode()
        scheduleHide()
    }

    /// Chọn chất lượng của tập đang xem, chỉ hiện khi tập có nhiều hơn một chất lượng.
    @ViewBuilder
    private var qualityPickerRow: some View {
        if let episode, let qualities = episode.qualities, qualities.count > 1 {
            settingsRow(
                icon: "4k.tv",
                title: "Chất lượng",
                detail: qualities.indices.contains(qualityIndex) ? qualities[qualityIndex].label : qualities[0].label
            ) {
                HStack(spacing: 6) {
                    ForEach(Array(qualities.enumerated()), id: \.offset) { index, quality in
                        qualityChip(label: quality.label, isSelected: index == qualityIndex) { selectQuality(index) }
                    }
                }
            }
        }
    }

    private func qualityChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.auroraViolet : Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("Chất lượng \(label)")
    }

    /// Lớp phụ đề app tự vẽ; tạm ẩn khi phụ đề gốc đang chạy trong PiP.
    @ViewBuilder
    private func subtitleOverlay(bottomInset: CGFloat) -> some View {
        if hasCurrentSubtitle, subtitlePreferences.enabled, !playback.nativeSubtitleActive,
           let subtitle = subtitles.currentText {
            VStack {
                Spacer()
                subtitleText(subtitle).padding(.bottom, bottomInset + subtitlePreferences.bottomSpacing)
            }
            .allowsHitTesting(false)
        }
    }

    /// Tách khỏi body: để nguyên trong chuỗi modifier thì trình biên dịch phải
    /// suy luận cả biểu thức khổng lồ và bị quá thời gian.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active { playback.recoverAfterForeground() }
        else { playback.prepareForSystemOverlay() }
    }

    private func applyPlaybackDefaults() {
        // Bật PiP thì chuyển sang phụ đề gốc (PiP mới hiện được), tắt PiP thì
        // quay lại lớp phụ đề theo thiết lập của người dùng.
        pipCoordinator.onActiveChanged = { [weak playback] active in
            playback?.setNativeSubtitles(active)
        }
        guard !hasAppliedPlaybackDefaults else { return }
        hasAppliedPlaybackDefaults = true
        autoAdvanceEpisodes = store.playbackDefaults.autoAdvanceEpisodes
        pictureInPictureEnabled = store.playbackDefaults.pictureInPicture
        pipCoordinator.setAutoStart(pictureInPictureEnabled && movie.allowPip != false)
        if subtitleCustomizationEnabled {
            let defaults = store.playbackDefaults.subtitlePreferences
            subtitlePreferences = defaults
        } else {
            subtitlePreferences = SubtitlePreferences()
        }
        stopTimer = StopTimer(rawValue: store.playbackDefaults.stopTimer) ?? .off
    }

    private func saveLocalWatchProgress() {
        guard let episode else { return }
        store.recordLocalHistory(movie: movie, episode: episode, serverName: server?.name, watchedSeconds: playback.currentTime, durationSeconds: playback.duration)
        lastHistorySaveAt = Date()
    }

    private func scheduleStopTimer() {
        stopTimerTask?.cancel()
        stopTimerRemaining = stopTimer.seconds.map(Int.init)
        guard let seconds = stopTimer.seconds else { return }
        stopTimerTask = Task { @MainActor in
            var remaining = Int(seconds)
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                stopTimerRemaining = remaining
            }
            guard !Task.isCancelled else { return }
            stopTimerRemaining = nil
            playback.pause()
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true; settingsOpen = false }
        }
    }

    private func handlePlaybackProgress() {
        if playback.currentTime > 0, Date().timeIntervalSince(lastHistorySaveAt) >= 10 {
            saveLocalWatchProgress()
        }
        guard playback.duration > 0, playback.currentTime >= playback.duration - 0.75, !didHandleEpisodeEnd else { return }
        didHandleEpisodeEnd = true
        let isTargetEpisode = stopAtEpisodeEnabled && episode.map { stopEpisodeKey($0) } == stopAtEpisodeID
        if stopTimer == .endOfEpisode || isTargetEpisode || !autoAdvanceEpisodes || episodeIndex + 1 >= episodes.count {
            playback.pause()
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true; settingsOpen = false }
            return
        }
        episodeIndex += 1
        controlsVisible = true
    }

    private func formatCountdown(_ value: Int) -> String {
        let hours = value / 3600
        let minutes = value / 60 % 60
        let seconds = value % 60
        return hours > 0 ? String(format: "%02d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }

    private func toggleControls() {
        guard !controlsLocked else { showLockIndicator(); return }
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func lockControls() {
        controlsLocked = true
        controlsVisible = false
        volumePopoverOpen = false
        quickMenu = nil
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { lockIndicatorVisible = true }
        scheduleLockIndicatorHide()
    }

    private func unlockControls() {
        lockHideTask?.cancel()
        controlsLocked = false
        withAnimation(.easeOut(duration: 0.2)) { lockIndicatorVisible = false; controlsVisible = true }
        scheduleHide()
    }

    private func showLockIndicator() {
        guard controlsLocked else { return }
        withAnimation(.easeOut(duration: 0.2)) { lockIndicatorVisible = true }
        scheduleLockIndicatorHide()
    }

    private func scheduleLockIndicatorHide() {
        lockHideTask?.cancel()
        lockHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, controlsLocked else { return }
            withAnimation(.easeIn(duration: 0.25)) { lockIndicatorVisible = false }
        }
    }

    /// Dọn trình phát khi thoát.
    ///
    /// Tách khỏi thân `body` có chủ đích: một closure dài nằm trong chuỗi modifier
    /// làm bộ kiểm tra kiểu của Swift bỏ cuộc — đúng lỗi build
    /// "unable to type-check this expression in reasonable time" ở dòng này.
    private func handlePlayerDisappear() {
        hideTask?.cancel(); lockHideTask?.cancel(); stopTimerTask?.cancel(); adjustmentHideTask?.cancel()
        if scenePhase == .active {
            // Stop the picture at once, then let the dismissal animation
            // finish before the expensive part: releasing the item,
            // deactivating the audio session, writing the resume point.
            // Doing all of that during the animation is what made leaving
            // the player feel sticky.
            playback.pauseForDismissal()
            // Everything the deferred work needs is read *now*. Touching
            // the view's environment after the view has been dismantled
            // traps ("No Observable object of type CinemaStore found"),
            // and that trap is what made the app vanish on the way back
            // from the player. Capturing the store and the values first
            // keeps the deferred work independent of the view's lifetime.
            let store = self.store
            let movie = self.movie
            let episode = self.episode
            let serverName = self.server?.name
            let playback = self.playback
            if !didScheduleTeardown {
                didScheduleTeardown = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    if let episode {
                        store.recordLocalHistory(
                            movie: movie,
                            episode: episode,
                            serverName: serverName,
                            watchedSeconds: playback.currentTime,
                            durationSeconds: playback.duration
                        )
                    }
                    playback.shutdown()
                }
            }
        }
        // A handoff keeps the landscape orientation for the incoming
        // player; a normal exit goes back to portrait.
        if !handingOffToRelated { forcePortrait() }
    }

    /// Ghi lại tuỳ chọn phụ đề, đọc môi trường khi view còn đang hiện.
    private func handleSubtitlePreferencesChange(_ value: SubtitlePreferences) {
        guard subtitleCustomizationEnabled else { return }
        let store = self.store
        DispatchQueue.main.async {
            store.updateSubtitlePreferences(value)
        }
        subtitles.update(time: playback.currentTime, bilingual: false)
    }

    private func handleStopAtEpisodeToggle(_ enabled: Bool) {
        if enabled, stopAtEpisodeID == nil {
            stopAtEpisodeID = episode.map { stopEpisodeKey($0) } ?? selectableStopEpisodes.first.map { stopEpisodeKey($0) }
        }
        scheduleStopTimer()
    }

    /// Đang tải nguồn thì không đếm giờ ẩn công cụ; vừa tải xong mới bắt đầu đếm.
    private func handleLoadingChange(_ isLoading: Bool) {
        if isLoading { hideTask?.cancel() } else { scheduleHide() }
    }

    /// Nguồn lỗi: giữ công cụ và thông báo lỗi (kèm nút Trở lại) trên màn hình.
    private func handlePlaybackErrorChange() {
        guard playback.errorMessage != nil else { return }
        hideTask?.cancel()
        controlsVisible = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard picker == nil, !volumePopoverOpen, !settingsOpen else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            // Chỉ ẩn khi phim đã chạy thật: đang tải nguồn hoặc đang báo lỗi thì
            // giữ công cụ (kèm nút Trở lại) cho người xem.
            guard playback.isPlaying,
                  !playback.isLoading,
                  playback.errorMessage == nil,
                  picker == nil else { return }
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
        }
    }

    private func forceLandscape() {
        forceOrientation(.landscapeRight)
    }

    private func forcePortrait() {
        forceOrientation(.portrait)
    }

    private func forceOrientation(_ orientation: UIInterfaceOrientation) {
        let isLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        // No `UIDevice.setValue(_:forKey:"orientation")` here: that KVC hack is
        // undefined behaviour on iOS 16+ and crashed the app intermittently. The
        // delegate lock plus the geometry request are enough.
        CinemoraAppDelegate.orientationLock = isLandscape ? .landscape : .portrait
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           #available(iOS 16.0, *) {
            let mask: UIInterfaceOrientationMask = isLandscape ? .landscape : .portrait
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let total = Int(value), hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct NativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let fit: CinemaPlayerScreen.VideoFit
    let pipCoordinator: PictureInPictureCoordinator

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fit.gravity
        pipCoordinator.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = fit.gravity
        pipCoordinator.attach(to: view.playerLayer)
    }
}

private extension CinemaPlayerScreen.VideoFit {
    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resize
        case .cover: return .resizeAspectFill
        }
    }
}

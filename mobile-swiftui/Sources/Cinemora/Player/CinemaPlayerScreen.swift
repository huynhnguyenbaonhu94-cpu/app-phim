import AVKit
import Combine
import SwiftUI
import UIKit
import WebKit

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
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var activeRequestID = UUID()
    private var seekRequestID = UUID()
    private var suppressLoadingUntil = Date.distantPast
    private var overlayRecoveryTask: Task<Void, Never>?
    private var resumeAfterOverlay = false
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        notificationTokens = [
            NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recoverAfterAudioRouteChange() }
            }
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            let requestID = MainActor.assumeIsolated { self?.activeRequestID }
            Task { @MainActor [weak self] in
                guard let self, let requestID, self.activeRequestID == requestID else { return }
                if time.seconds.isFinite, !self.isSeeking { self.currentTime = time.seconds }
                if let item = self.player.currentItem, item.duration.seconds.isFinite { self.duration = item.duration.seconds }
                self.isPlaying = self.player.timeControlStatus == .playing
                if !self.isSeeking, Date() >= self.suppressLoadingUntil {
                    self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                }
            }
        }
    }

    func shutdown() {
        loadTask?.cancel()
        loadTask = nil
        overlayRecoveryTask?.cancel()
        overlayRecoveryTask = nil
        resumeAfterOverlay = false
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
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true, options: [])
    }
    private func recoverAfterAudioRouteChange() {
        guard activeURL != nil, isPlaying else { return }
        configureAudioSession()
        // Công tắc chuông/im lặng chỉ đổi audio route. Giữ nguyên item và
        // vị trí hiện tại, không replace/reload để tránh màn hình đen.
        player.play()
        isPlaying = true
    }
    func load(_ episode: MovieEpisode, startAt: Double? = nil) {
        configureAudioSession()
        loadTask?.cancel()
        activeRequestID = UUID()
        let requestID = activeRequestID
        seekRequestID = UUID()
        isSeeking = false
        suppressLoadingUntil = .distantPast
        player.pause()
        errorMessage = nil; currentTime = 0; duration = 0
        itemObservation = nil
        guard let url = episode.streamURL else {
            player.pause(); player.replaceCurrentItem(with: nil); activeURL = nil
            isLoading = false
            if episode.embedURL == nil { errorMessage = "Tập này hiện chưa có đường dẫn phát." }
            return
        }
        activeURL = url
        isLoading = true
        let item = AVPlayerItem(url: url)
        // Video đã đăng render subtitle bằng SubtitleController bên dưới.
        // Không cho AVPlayer tự chọn legible track, nếu không sẽ xuất hiện
        // một subtitle hệ thống phía dưới và một subtitle tùy chỉnh phía trên.
        if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            item.select(nil, in: group)
        }
        item.preferredForwardBufferDuration = 8
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.activeRequestID == requestID else { return }
                switch item.status {
                case .readyToPlay:
                    if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                        item.select(nil, in: group)
                    }
                    self.loadTask?.cancel(); self.errorMessage = nil; self.isLoading = false
                    if let startAt, startAt > 0, startAt.isFinite {
                        let duration = item.duration.seconds
                        let safeStart = duration.isFinite && duration > 1 ? min(startAt, duration - 1) : startAt
                        self.seek(to: safeStart)
                    }
                case .failed:
                    self.loadTask?.cancel(); self.isLoading = false; self.activeURL = nil
                    self.errorMessage = item.error?.localizedDescription ?? "Nguồn HLS không phát được trên thiết bị này."
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        player.defaultRate = playbackRate
        player.rate = playbackRate
        isPlaying = true
        loadTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled, self.activeRequestID == requestID, self.isLoading else { return }
            self.isLoading = false
            self.errorMessage = "Nguồn phát phản hồi quá lâu. Hãy thử tập hoặc nguồn khác."
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
        player.play()
        isPlaying = true
        resumeAfterOverlay = false
    }
    func togglePlayback() {
        if player.timeControlStatus == .playing { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func pause() {
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
        let target = max(0, seconds)
        seekRequestID = UUID()
        let requestID = seekRequestID
        isSeeking = true
        isLoading = false
        suppressLoadingUntil = Date().addingTimeInterval(1.2)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self else { return }
            Task { @MainActor in
                guard self.seekRequestID == requestID else { return }
                if finished {
                    let actual = self.player.currentTime().seconds
                    if actual.isFinite { self.currentTime = actual }
                }
                self.isSeeking = false
                self.isLoading = false
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
    private var cues: [SubtitleCue] = []
    private var bilingualCues: [SubtitleCue] = []
    private var loadTask: Task<Void, Never>?
    func load(url: URL?, bilingualURL: URL? = nil) {
        loadTask?.cancel(); cues = []; bilingualCues = []; currentText = nil
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
        }
    }
    private static func fetchText(_ url: URL?) async -> String? {
        guard let url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            return String(data: data, encoding: .utf8)
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

    private static func parse(_ source: String) -> [SubtitleCue] {
        let blocks = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count >= 2 else { return nil }
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let rightParts = right.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let start = parseTime(parts[0]), let end = parseTime(rightParts.first.map(String.init) ?? "") else { return nil }
            let inlineText = rightParts.count > 1 ? String(rightParts[1]) : ""
            let followingText = lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = followingText.isEmpty ? inlineText : followingText
            guard !text.isEmpty else { return nil }
            return SubtitleCue(start: start, end: end, text: text)
        }.sorted { $0.start < $1.start }
    }
    private static func parseTime(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}

final class PictureInPictureCoordinator: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var isSupported = false
    @Published private(set) var isActive = false
    private var controller: AVPictureInPictureController?

    @MainActor
    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if controller?.playerLayer !== layer {
            guard let next = AVPictureInPictureController(playerLayer: layer) else { return }
            next.delegate = self
            next.canStartPictureInPictureAutomaticallyFromInline = true
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
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled, let self, let controller = self.controller, controller.isPictureInPicturePossible else { return }
                controller.startPictureInPicture()
            }
        }
    }

    @MainActor
    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.isActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.isActive = false }
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
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = PlaybackController()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @StateObject private var subtitles = SubtitleController()
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
    @State private var stopTimer: StopTimer = .off
    @State private var stopAtEpisodeEnabled = false
    @State private var stopAtEpisodeID: String?
    @State private var autoAdvanceEpisodes = true
    @State private var pictureInPictureEnabled = true
    @State private var relatedRecommendationsVisible = false
    @State private var selectedRelatedMovie: Movie?
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
                if playback.activeURL != nil {
                    NativeVideoSurface(player: playback.player, fit: videoFit, pipCoordinator: pipCoordinator).ignoresSafeArea().accessibilityLabel("Đang phát \(movie.name)")
                    if hasCurrentSubtitle, subtitlePreferences.enabled, let subtitle = subtitles.currentText {
                        VStack { Spacer(); subtitleText(subtitle).padding(.bottom, proxy.safeAreaInsets.bottom + subtitlePreferences.bottomSpacing) }
                            .allowsHitTesting(false)
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { if controlsLocked { controlsLocked = false; controlsVisible = true } else { toggleControls() } }
                } else if let embed = episode?.embedURL, selectedRelatedMovie == nil {
                    EmbedWebPlayer(url: embed).ignoresSafeArea()
                } else {
                    PosterArt(url: movie.backdropURL).ignoresSafeArea().overlay(Color.black.opacity(0.4))
                }

                if playback.activeURL != nil || episode?.embedURL != nil {
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
                        if playback.isLoading && !playback.isSeeking { ProgressView("Đang tải nguồn phát…").tint(.white).foregroundStyle(.white).padding(18).cinemaGlass(in: Capsule(), tint: .black.opacity(0.42)) }
                        if let error = playback.errorMessage {
                            errorCard(error)
                        } else if episode?.streamURL == nil && episode?.embedURL == nil {
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
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        handleAdjustmentDrag(value, width: proxy.size.width, height: proxy.size.height)
                    }
                    .onEnded { _ in finishAdjustmentGesture() }
            )
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: picker != nil)
            .animation(.easeInOut(duration: 0.2), value: controlsVisible)
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: settingsOpen)
            .onChange(of: episodeIndex) { _, _ in loadCurrentEpisode() }
            .onChange(of: serverIndex) { _, _ in
                if episodeIndex != 0 { episodeIndex = 0 }
                else { loadCurrentEpisode() }
            }
            .onChange(of: playback.isPlaying) { _, isPlaying in if isPlaying { scheduleHide() } }
            .onChange(of: playback.currentTime) { _, time in
                subtitles.update(time: time, bilingual: false)
                handlePlaybackProgress()
            }
            .onChange(of: subtitlePreferences) { _, value in
                guard subtitleCustomizationEnabled else { return }
                DispatchQueue.main.async {
                    store.playbackDefaults.subtitlePreferences = value
                    store.savePlaybackDefaults()
                }
                subtitles.update(time: playback.currentTime, bilingual: false)
            }
            .onChange(of: stopTimer) { _, _ in scheduleStopTimer() }
            .onChange(of: stopAtEpisodeEnabled) { _, enabled in
                if enabled, stopAtEpisodeID == nil {
                    stopAtEpisodeID = episode.map { stopEpisodeKey($0) } ?? selectableStopEpisodes.first.map { stopEpisodeKey($0) }
                }
                scheduleStopTimer()
            }
            .onChange(of: stopAtEpisodeID) { _, _ in scheduleStopTimer() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { playback.recoverAfterForeground() }
                else { playback.prepareForSystemOverlay() }
            }
            .onAppear { applyPlaybackDefaults(); loadCurrentEpisode(); scheduleHide() }
            .task {
                await store.loadHome()
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                forceLandscape()
            }
            .onDisappear {
                saveLocalWatchProgress(); hideTask?.cancel(); lockHideTask?.cancel(); stopTimerTask?.cancel(); adjustmentHideTask?.cancel()
                if scenePhase == .active { playback.shutdown() }
                forcePortrait()
            }
            .statusBarHidden(true)
        }
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(item: $selectedRelatedMovie, onDismiss: {
            // Khi đóng trang chi tiết phim liên quan, thoát luôn player A.
            dismiss()
        }) { related in
            MovieDetailScreen(slug: related.slug, autoPlayOnLoad: true)
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
    }

    private var topBar: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).frame(width: 42, height: 42) }
                .buttonStyle(.plain).foregroundStyle(.white).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Trở lại")
            VStack(alignment: .leading, spacing: 3) {
                Text(movie.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                Text("\(episode?.name ?? "Chọn tập")  ·  \(server?.name ?? "Nguồn")").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.66)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { withAnimation { picker = .episodes }; controlsVisible = true } label: { Image(systemName: "list.bullet").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42) }
                .buttonStyle(.plain).foregroundStyle(.white).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Danh sách tập")
            if servers.count > 1 {
                Button { withAnimation { picker = .sources }; controlsVisible = true } label: { Image(systemName: "square.stack.3d.up").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42) }
                    .buttonStyle(.plain).foregroundStyle(.white).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Chọn nguồn phát")
            }
            if pictureInPictureEnabled && movie.allowPip != false && pipCoordinator.isSupported {
                Button { pipCoordinator.isActive ? pipCoordinator.stop() : pipCoordinator.start(); scheduleHide() } label: {
                    Image(systemName: pipCoordinator.isActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.plain).foregroundStyle(pipCoordinator.isActive ? Color.cinemaInk : .white)
                .background(pipCoordinator.isActive ? Color.cinemaAccent : Color.black.opacity(0.36), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
                .accessibilityLabel(pipCoordinator.isActive ? "Thoát Picture-in-Picture" : "Bật Picture-in-Picture")
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { relatedRecommendationsVisible = true }
                hideTask?.cancel()
            } label: {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .cinemaGlass(in: Circle(), tint: .black.opacity(0.36))
            .accessibilityLabel("Video liên quan")
            quickControl(icon: "rectangle.on.rectangle", title: "Tỷ lệ", value: videoFit.rawValue, menu: .videoFit)
            quickControl(icon: "speedometer", title: "Tốc độ", value: playbackRateLabel, menu: .playbackRate)
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if !visibleSettingsTabs.contains(settingsTab) {
                        settingsTab = visibleSettingsTabs[0]
                    }
                    settingsOpen.toggle()
                    quickMenu = nil
                    volumePopoverOpen = false
                }
                if settingsOpen { hideTask?.cancel() } else { scheduleHide() }
            } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
            }
            .foregroundStyle(settingsOpen ? Color.cinemaInk : .white).buttonStyle(.plain)
            .background(settingsOpen ? Color.cinemaAccent : Color.black.opacity(0.36), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(settingsOpen ? 0.35 : 0.14), lineWidth: 0.8))
            .accessibilityLabel("Cài đặt phát video")
            Button { lockControls() } label: {
                Image(systemName: "lock").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
            }
            .foregroundStyle(.white).buttonStyle(.plain).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Khóa điều khiển")
            }
            if let quickMenu { quickMenuPanel(quickMenu) }
        }
    }

    private var cinemoraLogo: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles.tv.fill").font(.system(size: 13, weight: .black))
            Text("CINEMORA").font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).frame(height: 42)
        .background(.black.opacity(0.36), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
        .accessibilityLabel("Cinemora")
    }

    private var cinemoraWatermark: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles.tv.fill").font(.system(size: 12, weight: .black))
            Text("CINEMORA").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 10).frame(height: 32)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.28), radius: 5)
    }

    private var playbackRateLabel: String {
        playback.playbackRate == 1 ? "1x" : "\(formatRate(playback.playbackRate))x"
    }

    private var hasCurrentSubtitle: Bool {
        guard subtitleCustomizationEnabled, let episode else { return false }
        return episode.subtitleURL != nil
    }

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
            withAnimation(.easeOut(duration: 0.18)) {
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
            .foregroundStyle(quickMenu == menu ? Color.cinemaInk : .white)
            .frame(width: 52, height: 42)
            .background(quickMenu == menu ? Color.cinemaAccent : Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(quickMenu == menu ? 0.35 : 0.14), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder
    private func quickMenuPanel(_ menu: QuickMenu) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(menu == .videoFit ? "TỶ LỆ KHUNG HÌNH" : "TỐC ĐỘ PHÁT")
                    .font(.system(size: 9, weight: .black, design: .rounded)).tracking(1.2).foregroundStyle(Color.cinemaAccent)
                Spacer(minLength: 20)
                Button { withAnimation(.easeOut(duration: 0.18)) { quickMenu = nil }; scheduleHide() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("Đóng lựa chọn")
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
        .padding(12)
        .frame(width: 260)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
    }

    private func quickOption(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.18)) { quickMenu = nil }
            scheduleHide()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(selected ? Color.cinemaAccent : .white.opacity(0.45))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(detail).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.52))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(minHeight: 39)
            .background(selected ? Color.cinemaAccent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(subtitlePreferences.font)
            .foregroundStyle(subtitlePreferences.textColor)
            .multilineTextAlignment(subtitlePreferences.textAlignment)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: subtitlePreferences.frameAlignment)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: subtitlePreferences.outlineWidth)
            .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: -subtitlePreferences.outlineWidth)
    }

    private var settingsOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { settingsOpen = false }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                Text("Cài đặt").font(.system(size: 17, weight: .black, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.18)) { settingsOpen = false }; scheduleHide() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.68)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).background(.white.opacity(0.07), in: Circle()).accessibilityLabel("Đóng cài đặt")
            }
            settingsTabs
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            settingsTabContent
        }
        .padding(18)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.2), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.48), radius: 28, x: -8, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { }
    }

    private var settingsTabs: some View {
        HStack(spacing: 4) {
            ForEach(visibleSettingsTabs) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { settingsTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .bold))
                        Text(tab.rawValue).font(.system(size: 8, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(effectiveSettingsTab == tab ? Color.cinemaInk : .white.opacity(0.6))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(effectiveSettingsTab == tab ? Color.cinemaAccent : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch effectiveSettingsTab {
        case .audio:
            settingsRow(icon: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Âm lượng", detail: playback.isMuted ? "Đang tắt tiếng" : "\(Int(volume * 100))%") {
                HStack(spacing: 7) {
                    Slider(value: $volume, in: 0...1).tint(Color.cinemaAccent).frame(width: 130).onChange(of: volume) { _, value in playback.setVolume(value) }
                    Button { playback.toggleMute() } label: { Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(Color.cinemaAccent) }.buttonStyle(.plain)
                }
            }
        case .subtitle:
            if hasCurrentSubtitle {
                ScrollView(.vertical, showsIndicators: false) {
                    subtitlePreview
                    SubtitlePreferencesEditor(preferences: $subtitlePreferences, compact: true).padding(.vertical, 2)
                }.frame(minHeight: 245, maxHeight: 390, alignment: .top)
            }
        case .display:
            VStack(alignment: .leading, spacing: 10) {
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
                .tint(Color.cinemaAccent)
            }
        case .speed:
            VStack(alignment: .leading, spacing: 8) {
                settingsLabel(icon: "speedometer", title: "Tốc độ phát", detail: "Đang chọn \(playbackRateLabel)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button { playback.setPlaybackRate(Float(rate)); scheduleHide() } label: {
                            Text(rate == 1 ? "Bình thường" : "\(formatRate(Float(rate)))x").font(.system(size: 14, weight: .bold)).foregroundStyle(playback.playbackRate == Float(rate) ? Color.cinemaInk : .white.opacity(0.78)).frame(maxWidth: .infinity).frame(height: 42).background(playback.playbackRate == Float(rate) ? Color.cinemaAccent : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }
            }
        case .general:
            VStack(alignment: .leading, spacing: 10) {
                settingsRow(icon: "moon.zzz.fill", title: "Tự dừng phát", detail: "Dừng sau một khoảng thời gian") { Picker("Tự dừng phát", selection: $stopTimer) { ForEach(StopTimer.allCases) { value in Text(value.rawValue).tag(value) } }.labelsHidden().pickerStyle(.menu).tint(Color.cinemaAccent) }
                if let stopTimerRemaining {
                    HStack(spacing: 7) { Image(systemName: "timer").foregroundStyle(Color.cinemaAccent); Text("Tự dừng sau \(formatCountdown(stopTimerRemaining))").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white); Spacer() }
                }
                Toggle(isOn: $stopAtEpisodeEnabled) {
                    settingsLabel(icon: "stop.circle.fill", title: "Dừng ở tập đã chọn", detail: "Tự chuyển đến tập mục tiêu rồi dừng")
                }.tint(Color.cinemaAccent)
                if stopAtEpisodeEnabled { episodeStopSelector }
                Toggle(isOn: $autoAdvanceEpisodes) { settingsLabel(icon: "forward.end.fill", title: "Tự động chuyển tập", detail: "Phát tập kế tiếp khi tập hiện tại kết thúc") }.tint(Color.cinemaAccent)
            }
        }
    }

    private var subtitlePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XEM TRƯỚC REALTIME")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.cinemaAccent)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.blue.opacity(0.34), .black.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 92)
                Text("Đây là phụ đề xem trước")
                    .font(subtitlePreferences.font)
                    .foregroundStyle(subtitlePreferences.textColor)
                    .multilineTextAlignment(subtitlePreferences.textAlignment)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: subtitlePreferences.frameAlignment)
                    // Preview dùng tỷ lệ thu nhỏ, nhưng luôn di chuyển cùng
                    // chiều với subtitle thật khi đổi khoảng cách phía dưới.
                    .padding(.bottom, min(max(subtitlePreferences.bottomSpacing * 0.55, 4), 72))
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: subtitlePreferences.outlineWidth)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: -subtitlePreferences.outlineWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func settingsEmpty(icon: String, text: String) -> some View {
        HStack(spacing: 9) { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.cinemaAccent); Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true) }
            .padding(.vertical, 10)
    }

    private var episodeStopSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHỌN TẬP DỪNG").font(.system(size: 8, weight: .black, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.48)).padding(.leading, 4)
            if selectableStopEpisodes.isEmpty {
                Text("API chưa trả về danh sách tập cho phim này. Hãy đóng trình phát và mở lại phim để tải dữ liệu mới.")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 5) {
                        ForEach(selectableStopEpisodes.indices, id: \.self) { index in
                            let item = selectableStopEpisodes[index]
                            Button {
                                stopAtEpisodeID = stopEpisodeKey(item)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: stopAtEpisodeID == stopEpisodeKey(item) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(stopAtEpisodeID == stopEpisodeKey(item) ? Color.cinemaAccent : .white.opacity(0.42))
                                    Text(item.name).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 9).frame(minHeight: 32)
                                .background(stopAtEpisodeID == stopEpisodeKey(item) ? Color.cinemaAccent.opacity(0.16) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                // `maxHeight` alone lets SwiftUI collapse this ScrollView to zero
                // height inside the settings VStack. Keep one row visible and
                // cap long episode lists so they remain scrollable.
                .frame(minHeight: 37, maxHeight: 142)
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
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.cinemaAccent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 38) {
            Button { playback.seek(to: max(0, playback.currentTime - 10)); scheduleHide() } label: { skipControl("gobackward.10") }
                .buttonStyle(.plain).accessibilityLabel("Lùi 10 giây")
            Button { playback.togglePlayback(); scheduleHide() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .black)).foregroundStyle(Color.cinemaInk)
                    .frame(width: 70, height: 70).background(Color.cinemaAccent, in: Circle())
                    .shadow(color: Color.cinemaAccent.opacity(0.24), radius: 22, y: 8)
            }.buttonStyle(.plain).accessibilityLabel(playback.isPlaying ? "Tạm dừng" : "Phát")
            Button { playback.seek(to: min(playback.duration, playback.currentTime + 10)); scheduleHide() } label: { skipControl("goforward.10") }
                .buttonStyle(.plain).accessibilityLabel("Tiến 10 giây")
        }
    }

    private func skipControl(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 52, height: 52).background(.black.opacity(0.35), in: Circle()).cinemaGlass(in: Circle(), tint: .white.opacity(0.06))
    }

    private func adjustmentHUD(for kind: AdjustmentKind) -> some View {
        VStack(spacing: 9) {
            Image(systemName: kind == .brightness ? "sun.max.fill" : (playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.cinemaAccent)
                .frame(width: 32, height: 32)
                .background(Color.cinemaAccent.opacity(0.14), in: Circle())
                .scaleEffect(adjustmentPulse ? 1.12 : 1)
            GeometryReader { proxy in
                let fillHeight = max(8, proxy.size.height * adjustmentValue)
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.16)).frame(width: 7)
                    Capsule().fill(Color.cinemaAccent).frame(width: 7, height: fillHeight)
                    Circle().fill(Color.cinemaAccent).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                        .shadow(color: Color.cinemaAccent.opacity(0.55), radius: 9)
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
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
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

    private func handleAdjustmentDrag(_ value: DragGesture.Value, width: CGFloat, height: CGFloat) {
        guard !controlsLocked, picker == nil, !settingsOpen, !relatedRecommendationsVisible else { return }
        guard value.startLocation.y > height * 0.22 else { return }
        if !isAdjustmentGestureActive {
            guard abs(value.translation.height) > max(8, abs(value.translation.width) * 0.75) else { return }
            isAdjustmentGestureActive = true
            let isBrightness = value.startLocation.x < width / 2
            adjustmentKind = isBrightness ? .brightness : .volume
            gestureStartValue = isBrightness ? Double(UIScreen.main.brightness) : volume
        }

        let nextValue = min(1, max(0, gestureStartValue - Double(value.translation.height / 340)))
        adjustmentValue = nextValue
        if adjustmentKind == .brightness {
            UIScreen.main.brightness = CGFloat(nextValue)
        } else {
            volume = nextValue
            playback.setVolume(nextValue)
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
                Text(formatTime(isScrubbing ? scrubValue : playback.currentTime)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).frame(width: 42, alignment: .leading)
                Slider(value: Binding(get: { isScrubbing ? scrubValue : playback.currentTime }, set: { scrubValue = $0; isScrubbing = true }), in: 0...max(1, playback.duration), onEditingChanged: { editing in
                    if editing {
                        scrubValue = playback.currentTime
                        isScrubbing = true
                    } else {
                        let target = scrubValue
                        isScrubbing = false
                        playback.seek(to: target)
                        scheduleHide()
                    }
                })
                    .tint(Color.cinemaAccent)
                Text(formatTime(playback.duration)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).frame(width: 42, alignment: .trailing)
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { volumePopoverOpen.toggle() }; scheduleHide() } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 43, height: 43)
                }
                .buttonStyle(.plain).cinemaGlass(in: Circle(), tint: .black.opacity(0.4))
                .accessibilityLabel("Điều chỉnh âm lượng")
            }
            .overlay(alignment: .bottomTrailing) {
                if volumePopoverOpen {
                    HStack(spacing: 10) {
                        Button { playback.toggleMute() } label: {
                            Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 34, height: 34)
                        }.buttonStyle(.plain).accessibilityLabel(playback.isMuted ? "Bật âm thanh" : "Tắt âm thanh")
                        Slider(value: $volume, in: 0...1, onEditingChanged: { editing in if !editing { scheduleHide() } })
                            .tint(Color.cinemaAccent).frame(width: 142)
                            .onChange(of: volume) { _, value in playback.setVolume(value) }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.7))
                    .offset(y: -49)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
                }
            }
            HStack {
                Text(movie.name).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.56)).lineLimit(1)
                Spacer()
                if let episode { Text(episode.name).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.cinemaAccent).lineLimit(1) }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 22)).foregroundStyle(Color.cinemaAccent)
            Text("Không thể phát video").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.66)).multilineTextAlignment(.center).lineLimit(3)
            Button("Trở lại") { dismiss() }.font(.system(size: 11, weight: .bold)).foregroundStyle(Color.cinemaInk).padding(.horizontal, 16).padding(.vertical, 9).background(Color.cinemaAccent, in: Capsule())
        }
        .padding(18).frame(maxWidth: 340).cinemaGlass(in: RoundedRectangle(cornerRadius: 24), tint: .black.opacity(0.54))
    }

    private var relatedRecommendationsOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionEyebrow(text: "CINEMORA · FULLSCREEN BROWSING")
                        Text("Video liên quan")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Khám phá thêm phim tương tự mà không cần rời trình phát")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { relatedRecommendationsVisible = false }
                        scheduleHide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đóng video liên quan")
                }

                if relatedMovies.isEmpty {
                    StateMessage(icon: "sparkles.tv", title: "Chưa có gợi ý", detail: "Hãy quay lại trang chủ để cập nhật danh sách phim.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 18) {
                            ForEach(relatedMovies) { related in
                                Button {
                                    openRelatedMovie(related)
                                } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        PosterArt(url: related.posterURL)
                                            .frame(height: 175)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14), lineWidth: 0.7))
                                        Text(related.name)
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text(related.originName ?? "Phim đề xuất")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func openRelatedMovie(_ related: Movie) {
        // Stop the current item before presenting another player so its audio
        // cannot continue underneath the related movie.
        saveLocalWatchProgress()
        playback.shutdown()
        subtitles.load(url: nil)
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            relatedRecommendationsVisible = false
        }
        if let onOpenRelated {
            // MovieDetailScreen thay player A bằng trang phim B. B tự mở
            // player, nên khi đóng có thể trở về đúng trang chi tiết B.
            onOpenRelated(related)
            return
        }
        selectedRelatedMovie = related
    }

    private func pickerOverlay(_ kind: PickerKind) -> some View {
        ZStack {
            Color.black.opacity(0.63).ignoresSafeArea().onTapGesture { withAnimation { picker = nil }; scheduleHide() }
            VStack(spacing: 14) {
                Capsule().fill(.white.opacity(0.36)).frame(width: 40, height: 4).padding(.top, 3)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionEyebrow(text: kind == .episodes ? "CINEMORA · TẬP PHIM" : "CINEMORA · CHẤT LƯỢNG")
                        Text(kind == .episodes ? "Danh sách tập" : "Chọn nguồn phát").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Đang phát: \(kind == .episodes ? (episode?.name ?? "") : (server?.name ?? ""))").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.57)).lineLimit(1)
                    }
                    Spacer()
                    Button { withAnimation { picker = nil }; scheduleHide() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 40, height: 40).background(.white.opacity(0.1), in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Đóng danh sách")
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 9)], spacing: 9) {
                        if kind == .episodes {
                                ForEach(episodes.indices, id: \.self) { index in
                                    pickerRow(number: index + 1, title: episodes[index].name, selected: index == episodeIndex) {
                                        episodeIndex = index
                                        controlsVisible = true
                                    }
                            }
                        } else {
                            ForEach(servers.indices, id: \.self) { index in
                                    pickerRow(number: index + 1, title: servers[index].name, selected: index == serverIndex) {
                                        serverIndex = index
                                        controlsVisible = true
                                    }
                            }
                        }
                    }
                }
                .frame(maxHeight: 330)
            }
            .padding(.horizontal, 21).padding(.top, 11).padding(.bottom, 18)
            .frame(maxWidth: 840).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .padding(.horizontal, 22)
        }
        .zIndex(10)
    }

    private func pickerRow(number: Int, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", number)).font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(selected ? Color.cinemaInk : Color.cinemaAccent)
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(selected ? Color.cinemaInk : .white.opacity(0.84)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cinemaInk) }
            }
            .padding(.horizontal, 12).frame(minHeight: 51)
            .background(selected ? Color.cinemaAccent : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
    }

    private func loadCurrentEpisode() {
        guard let episode else { return }
        didHandleEpisodeEnd = false
        let startAt = hasAppliedResumeTime ? nil : resumeTime
        subtitles.load(url: hasCurrentSubtitle ? episode.subtitleURL : nil, bilingualURL: nil)
        playback.load(episode, startAt: startAt)
        if startAt != nil { hasAppliedResumeTime = true }
        saveLocalWatchProgress()
    }

    private func applyPlaybackDefaults() {
        guard !hasAppliedPlaybackDefaults else { return }
        hasAppliedPlaybackDefaults = true
        autoAdvanceEpisodes = store.playbackDefaults.autoAdvanceEpisodes
        pictureInPictureEnabled = store.playbackDefaults.pictureInPicture
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

    private func scheduleHide() {
        hideTask?.cancel()
        guard picker == nil, !volumePopoverOpen, !settingsOpen else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if (playback.isPlaying || (episode?.streamURL == nil && episode?.embedURL != nil)) && picker == nil { withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false } }
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
        CinemoraAppDelegate.orientationLock = isLandscape ? .landscape : .portrait
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
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

private struct EmbedWebPlayer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .black; view.scrollView.isScrollEnabled = false
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url { uiView.load(URLRequest(url: url)) }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.evaluateJavaScript("document.querySelectorAll('video, audio').forEach(media => { media.pause(); media.removeAttribute('src'); media.load(); }); window.stop();", completionHandler: nil)
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

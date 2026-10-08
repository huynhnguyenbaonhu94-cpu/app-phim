import AVKit
import Combine
import SwiftUI
import UIKit

@MainActor
private final class TVPlaybackController: ObservableObject {
    let player = AVPlayer()
    private let separateAudioPlayer = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var currentURL: URL?
    private var currentAudioURL: URL?
    private var hasSeparateAudio = false
    private var userPaused = false
    private var syncTask: Task<Void, Never>?
    private var notificationTokens: [NSObjectProtocol] = []
    private var lastAudioCorrectionAt: Date = .distantPast

    init() {
        configureAudioSession()
        player.automaticallyWaitsToMinimizeStalling = true
        separateAudioPlayer.automaticallyWaitsToMinimizeStalling = true
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleAudioInterruption(note) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleAudioRouteChange() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recoverAfterForeground() }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handlePlayerFailure(note) }
            }
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                if time.seconds.isFinite { self.currentTime = time.seconds }
                self.isPlaying = self.player.rate > 0.01 && (!self.hasSeparateAudio || self.separateAudioPlayer.rate > 0.01)
                self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.correctSeparateAudioDriftIfNeeded()
            }
        }
    }

    func load(_ url: URL, audioURL: URL? = nil) {
        currentURL = url
        currentAudioURL = audioURL
        hasSeparateAudio = audioURL != nil
        userPaused = false
        lastAudioCorrectionAt = .distantPast
        syncTask?.cancel()
        itemObservation = nil
        player.pause()
        separateAudioPlayer.pause()
        isPlaying = false
        isLoading = true
        currentTime = 0
        player.isMuted = hasSeparateAudio
        let item = AVPlayerItem(url: url)
        // Không đọc mediaSelectionGroup ngay lúc vừa bấm mở player;
        // một số HLS tải metadata đồng bộ và làm nghẽn main thread.
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.disableEmbeddedSubtitles(in: item)
                    self.isLoading = false
                }
                if item.status == .failed { self.isLoading = false }
            }
        }
        player.replaceCurrentItem(with: item)
        if let audioURL {
            separateAudioPlayer.replaceCurrentItem(with: AVPlayerItem(url: audioURL))
            separateAudioPlayer.volume = player.volume
            separateAudioPlayer.isMuted = player.isMuted
        } else {
            separateAudioPlayer.replaceCurrentItem(with: nil)
        }
        player.playImmediately(atRate: 1)
        if hasSeparateAudio { separateAudioPlayer.playImmediately(atRate: 1) }
        isPlaying = true
    }

    private func disableEmbeddedSubtitles(in item: AVPlayerItem) {
        Task { @MainActor in
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                item.select(nil, in: group)
            }
        }
    }

    /// Rebuild both live items, then seek each one to its own live edge. This is
    /// more reliable than seeking the audio to the video's raw CMTime because
    /// two independent HLS playlists do not share the same media timeline.
    func syncToLiveEdge() {
        guard let currentURL else { return }
        let resume = !userPaused
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoading = true
            self.player.pause()
            self.separateAudioPlayer.pause()
            self.player.replaceCurrentItem(with: AVPlayerItem(url: currentURL))
            if let audioURL = self.currentAudioURL {
                self.separateAudioPlayer.replaceCurrentItem(with: AVPlayerItem(url: audioURL))
            }
            await self.waitForItemsReady()
            guard !Task.isCancelled else { return }
            self.seekBothToLiveEdge()
            self.isLoading = false
            if resume {
                self.player.playImmediately(atRate: 1)
                if self.hasSeparateAudio { self.separateAudioPlayer.playImmediately(atRate: 1) }
                self.isPlaying = true
            } else {
                self.userPaused = true
                self.isPlaying = false
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            userPaused = true
            player.pause(); separateAudioPlayer.pause(); isPlaying = false
        } else {
            userPaused = false
            // Resume both at the same stored live position. The next observer
            // pass only corrects a genuine drift, never a user pause.
            player.playImmediately(atRate: 1)
            if hasSeparateAudio { separateAudioPlayer.playImmediately(atRate: 1) }
            isPlaying = true
        }
    }

    func pause() {
        userPaused = true
        player.pause(); separateAudioPlayer.pause(); isPlaying = false
    }

    func setVolume(_ value: Double) {
        if hasSeparateAudio {
            separateAudioPlayer.volume = Float(value)
            player.volume = 0
        } else {
            player.volume = Float(value)
        }
    }

    func setMuted(_ muted: Bool) {
        if hasSeparateAudio {
            separateAudioPlayer.isMuted = muted
            player.isMuted = true
        } else {
            player.isMuted = muted
        }
    }

    private func correctSeparateAudioDriftIfNeeded() {
        guard hasSeparateAudio, !userPaused, isPlaying,
              player.rate > 0.01, separateAudioPlayer.rate > 0.01 else { return }
        guard let videoRange = player.currentItem?.seekableTimeRanges.last?.timeRangeValue,
              let audioRange = separateAudioPlayer.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        let videoLiveEdge = videoRange.end.seconds - 1.0
        let audioLiveEdge = audioRange.end.seconds - 1.0
        let videoLag = videoLiveEdge - CMTimeGetSeconds(player.currentTime())
        let audioLag = audioLiveEdge - CMTimeGetSeconds(separateAudioPlayer.currentTime())
        let lagDifference = audioLag - videoLag
        // Independent HLS playlists naturally fluctuate by a few hundred ms.
        // Repeated seeks can replay an AAC fragment and create crackling audio.
        guard abs(lagDifference) > 2.5,
              Date().timeIntervalSince(lastAudioCorrectionAt) > 5 else { return }
        lastAudioCorrectionAt = Date()
        if abs(lagDifference) > 2.5 {
            let target = max(audioRange.start.seconds, audioLiveEdge - max(0, videoLag))
            separateAudioPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func waitForItemsReady() async {
        for _ in 0..<40 {
            if Task.isCancelled { return }
            let videoReady = player.currentItem?.status == .readyToPlay
            let audioReady = !hasSeparateAudio || separateAudioPlayer.currentItem?.status == .readyToPlay
            if videoReady && audioReady { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func seekBothToLiveEdge() {
        seekToLiveEdge(player)
        if hasSeparateAudio { seekToLiveEdge(separateAudioPlayer) }
    }

    private func seekToLiveEdge(_ target: AVPlayer) {
        guard let range = target.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        let edge = max(range.start.seconds, range.end.seconds - 1.0)
        target.seek(to: CMTime(seconds: edge, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true, options: [])
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            player.pause(); separateAudioPlayer.pause(); isPlaying = false
        } else if type == .ended {
            configureAudioSession()
            if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume), !userPaused {
                resumeCurrentItems()
            }
        }
    }

    private func handleAudioRouteChange() {
        configureAudioSession()
        guard !userPaused, currentURL != nil else { return }
        // Đổi công tắc chuông/im lặng chỉ là thay đổi audio route. Không dựng
        // lại AVPlayer/HLS ở đây vì việc replace item có thể làm video đen.
        if player.currentItem?.status != .failed {
            resumeCurrentItems()
        }
    }

    private func resumeCurrentItems() {
        player.playImmediately(atRate: 1)
        if hasSeparateAudio { separateAudioPlayer.playImmediately(atRate: 1) }
        isPlaying = true
    }

    private func recoverAfterForeground() {
        configureAudioSession()
        guard !userPaused, currentURL != nil else { return }
        if player.currentItem?.status == .failed || (hasSeparateAudio && separateAudioPlayer.currentItem?.status == .failed) {
            syncToLiveEdge()
        } else if !isPlaying {
            player.playImmediately(atRate: 1)
            if hasSeparateAudio { separateAudioPlayer.playImmediately(atRate: 1) }
            isPlaying = true
        }
    }

    private func handlePlayerFailure(_ note: Notification) {
        guard let failedItem = note.object as? AVPlayerItem,
              failedItem === player.currentItem || failedItem === separateAudioPlayer.currentItem,
              !userPaused else { return }
        isLoading = true
        syncToLiveEdge()
    }

    func shutdown() {
        syncTask?.cancel()
        itemObservation = nil
        player.pause()
        separateAudioPlayer.pause()
        player.replaceCurrentItem(with: nil)
        separateAudioPlayer.replaceCurrentItem(with: nil)
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}

struct TVScreen: View {
    /// Held, not observed. `TVScreen` must not re-render whenever the shared
    /// store publishes, so the store is passed in as a plain property and only
    /// forwarded to the detail screen inside the player cover.
    let store: CinemaStore
    @Environment(TvStore.self) private var tv
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = TVPlaybackController()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @State private var selectedStreamID: Int?
    @State private var selectedStreamSnapshot: TvStream?
    @State private var selectedVideoID: Int?
    @State private var selectedVideoMovieSnapshot: Movie?
    @State private var selectedVideoEpisode = 0
    @State private var relatedMovieRoute: Movie?
    @State private var isMuted = false
    @State private var volume = 1.0
    @State private var isPlayerPresented = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var selectedStream: TvStream? {
        if let selectedStreamSnapshot { return selectedStreamSnapshot }
        guard let selectedStreamID else { return nil }
        return tv.streams.first { $0.id == selectedStreamID }
    }

    private var selectedVideo: TvVideo? {
        guard let selectedVideoID else { return nil }
        return tv.videos.first { $0.id == selectedVideoID }
    }

    /// Posted TV videos use the same movie player as catalog movies. Each
    /// quality is represented as a source, while all sources expose the same
    /// episode list. This keeps the player UI and playback behavior in one
    /// place instead of maintaining a second, less capable video player.
    private var selectedVideoMovie: Movie? { selectedVideoMovieSnapshot }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    CinemaHeader(eyebrow: "CINEMORA LIVE", title: "TRUYỀN HÌNH")
                        .auroraReveal(0)

                    if tv.loading && tv.streams.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeading(eyebrow: "KÊNH TRỰC TUYẾN", title: "Đang tải kênh")
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(0..<4, id: \.self) { _ in
                                    VStack(alignment: .leading, spacing: 9) {
                                        SkeletonBlock(cornerRadius: 20)
                                            .aspectRatio(1.5, contentMode: .fit)
                                        SkeletonBlock(cornerRadius: 6)
                                            .frame(height: 11)
                                            .frame(maxWidth: 120, alignment: .leading)
                                    }
                                }
                            }
                        }
                    } else if tv.streams.isEmpty {
                        StateMessage(icon: "tv", title: "Chưa có kênh truyền hình", detail: tv.error ?? "Admin chưa thêm stream nào.")
                    } else {
                        SectionHeading(eyebrow: "KÊNH TRỰC TUYẾN", title: "Chọn kênh để xem")
                            .auroraReveal(1)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(tv.streams.enumerated()), id: \.element.id) { index, stream in
                                TVChannelCard(stream: stream, isSelected: stream.id == selectedStream?.id) {
                                    selectedStreamID = stream.id
                                    selectedStreamSnapshot = stream
                                    selectedVideoID = nil
                                    selectedVideoMovieSnapshot = nil
                                    relatedMovieRoute = nil
                                    isPlayerPresented = true
                                }
                                .auroraReveal(index % 8)
                            }
                        }
                    }

                    if !tv.videos.isEmpty {
                        SectionHeading(eyebrow: "VIDEO", title: "Video đã đăng")
                            .auroraReveal(2)
                        LazyVStack(spacing: 11) {
                            ForEach(Array(tv.videos.enumerated()), id: \.element.id) { index, video in
                                TVVideoRow(video: video) {
                                    selectedVideoID = video.id
                                    selectedVideoMovieSnapshot = nil
                                    selectedVideoEpisode = 0
                                    selectedStreamID = nil
                                    selectedStreamSnapshot = nil
                                    relatedMovieRoute = nil
                                    Task { @MainActor in
                                        // Build the TvVideo -> Movie snapshot off the
                                        // main thread. The value and its type are
                                        // spelled out so the type checker does not
                                        // have to solve the whole async expression at
                                        // once (that was a hard compile error).
                                        let source = video
                                        let snapshot: Movie = await Task.detached(priority: .userInitiated) {
                                            source.asPlayerMovie
                                        }.value
                                        guard selectedVideoID == video.id else { return }
                                        selectedVideoMovieSnapshot = snapshot
                                        isPlayerPresented = true
                                    }
                                }
                                .auroraReveal(index % 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .refreshable { await tv.refresh() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await tv.startLive() }
        .onChange(of: scenePhase) { _, phase in
            // Only backgrounding the app closes the live connection. Switching
            // tabs must not: doing so restarted the SSE stream and refetched
            // both lists every time the user came back to this tab.
            if phase == .active { Task { await tv.refresh() } }
            else { tv.stopLive() }
        }
        .onChange(of: tv.streams) { _, streams in
            // During playback, keep the selected media snapshot stable. A
            // foreground refresh must not replace it or pick another channel.
            guard !isPlayerPresented else { return }
            // Video đã đăng cũng đặt selectedStreamID = nil. Không tự chọn
            // kênh live khi danh sách được refresh (ví dụ app quay lại từ
            // Control Center), nếu không fullScreenCover sẽ đổi player giữa chừng.
            if selectedStreamID == nil {
                if selectedVideoID == nil { selectedStreamID = streams.first?.id }
            } else if !streams.contains(where: { $0.id == selectedStreamID }) {
                selectedStreamID = streams.first?.id
            }
        }
        .onChange(of: isPlayerPresented) { _, presented in
            if !presented {
                if pipCoordinator.isActive { pipCoordinator.stop() }
                playback.shutdown()
            }
        }
        .onDisappear { playback.shutdown() }
        .fullScreenCover(isPresented: $isPlayerPresented, onDismiss: {
            if relatedMovieRoute != nil {
                relatedMovieRoute = nil
            }
            selectedVideoID = nil
            selectedVideoMovieSnapshot = nil
            selectedStreamSnapshot = nil
            if selectedStreamID == nil || !tv.streams.contains(where: { $0.id == selectedStreamID }) {
                selectedStreamID = tv.streams.first?.id
            }
        }) {
            Group {
                if let relatedMovieRoute {
                    MovieDetailScreen(
                        slug: relatedMovieRoute.slug,
                        autoPlayOnLoad: true,
                        onExitRelated: { isPlayerPresented = false }
                    )
                        .environment(store)
                        .preferredColorScheme(.dark)
                } else if let selectedStream {
                    TVFullscreenPlayer(stream: selectedStream, playback: playback, pipCoordinator: pipCoordinator, isMuted: $isMuted, volume: $volume, isFullscreen: $isPlayerPresented)
                } else if let selectedVideoMovie {
                    // Tránh dựng TvVideo -> Movie hai lần trong cùng một lần mở
                    // fullscreen, vốn gây cảm giác đứng hình với video nhiều tập.
                    let servers = selectedVideoMovie.availableServers
                    CinemaPlayerScreen(
                        movie: selectedVideoMovie,
                        servers: servers,
                        initialServer: 0,
                        initialEpisode: selectedVideoEpisode,
                        subtitleCustomizationEnabled: true,
                        onOpenRelated: { related in relatedMovieRoute = related }
                    )
                }
            }
            .id(relatedMovieRoute?.id ?? "tv-player-\(selectedVideoID ?? selectedStreamID ?? 0)")
        }
    }

    private func play(_ stream: TvStream) {
        guard let url = stream.streamURL else { return }
        playback.load(url, audioURL: stream.audioURL)
        playback.setVolume(volume)
        playback.setMuted(isMuted)
    }

}

private extension TvVideo {
    /// Convert the TV API shape into the shared player shape. URLs are
    /// resolved through tvStreamURL so protected TV hosts receive the same
    /// proxy treatment as live TV streams.
    var asPlayerMovie: Movie {
        var qualityLabels: [String] = []
        for quality in episodes.flatMap(\.qualities) where !qualityLabels.contains(quality.label) {
            qualityLabels.append(quality.label)
        }
        let servers = qualityLabels.compactMap { label -> MovieServer? in
            let qualityEpisodes = episodes.compactMap { tvEpisode -> MovieEpisode? in
                guard let quality = tvEpisode.qualities.first(where: { $0.label == label }),
                      let streamURL = quality.streamURL else { return nil }
                return MovieEpisode(
                    name: tvEpisode.name,
                    slug: "tv-\(id)-episode-\(tvEpisode.id)-quality-\(quality.id)",
                    filename: "",
                    embedUrl: nil,
                    streamUrl: streamURL.absoluteString,
                    subtitleUrl: (quality.subtitleURL ?? quality.languageSubtitleTracks.first?.subtitleURL ?? tvEpisode.subtitleURL)?.absoluteString,
                    bilingualSubtitleUrl: (quality.bilingualSubtitleURL ?? tvEpisode.bilingualSubtitleURL)?.absoluteString
                )
            }
            guard !qualityEpisodes.isEmpty else { return nil }
            return MovieServer(name: label, isAi: false, episodes: qualityEpisodes)
        }
        return Movie(
            apiID: "tv-video-\(id)",
            slug: "tv-video-\(id)",
            name: name,
            originName: nil,
            poster: logoUrl,
            backdrop: logoUrl,
            year: nil,
            quality: nil,
            episodeCurrent: episodes.count > 1 ? "\(episodes.count) tập" : "Tập 1",
            episodeTotal: episodes.count,
            time: nil,
            lang: nil,
            description: description,
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
            servers: servers,
            allowPip: allowPip,
            episodeGroups: nil
        )
    }
}

private enum TVVideoFit: String, CaseIterable, Identifiable {
    case fit = "Vừa"
    case cover = "Phủ"
    case fill = "Đầy"

    var id: String { rawValue }
    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit: return .resizeAspect
        case .cover: return .resizeAspectFill
        case .fill: return .resize
        }
    }
}

private enum TVQuickMenu: Equatable { case videoFit }

// MARK: - Live channel card

private struct TVChannelCard: View {
    let stream: TvStream
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                PosterArt(url: stream.posterURL)
                    .aspectRatio(1.5, contentMode: .fit)
                    .overlay {
                        LinearGradient(
                            colors: [Color.black.opacity(0.25), Color.clear, Color.black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            LivePulse(color: stream.isOnline ? .auroraMint : .auroraAmber, size: 6)
                            Text(stream.isOnline ? "LIVE" : "CHỜ NGUỒN")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7))
                        .padding(9)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            EqualizerBars(color: .auroraMint, bars: 4)
                                .padding(10)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.auroraMint.opacity(0.7) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 1.4 : 0.8
                            )
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 14, y: 9)
                    // Zero radius while unselected: the grid should not pay for a
                    // second, fully transparent shadow pass on every card.
                    .shadow(color: isSelected ? Color.auroraMint.opacity(0.3) : .clear, radius: isSelected ? 20 : 0, y: isSelected ? 8 : 0)

                Text(stream.name)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.auroraPress(scale: 0.97))
        .animation(Motion.gentle, value: isSelected)
    }
}

// MARK: - Live player

private struct TVPlayerView: View {
    let stream: TvStream
    @ObservedObject var playback: TVPlaybackController
    let pipCoordinator: PictureInPictureCoordinator
    @Binding var isMuted: Bool
    @Binding var volume: Double
    @Binding var isFullscreen: Bool
    @State private var controlsVisible = true
    @State private var volumePopoverOpen = false
    @State private var hideTask: Task<Void, Never>?
    @State private var videoFit: TVVideoFit = .fit
    @State private var quickMenu: TVQuickMenu?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                TVNativeVideoSurface(player: playback.player, fit: videoFit, pipCoordinator: pipCoordinator)
                    .accessibilityLabel("Đang phát \(stream.name)")
                Color.clear.contentShape(Rectangle()).onTapGesture { toggleControls() }
                if controlsVisible {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        if playback.isLoading {
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
                        Spacer()
                        centerControls
                        Spacer()
                        bottomControls
                    }
                    .padding(.horizontal, max(18, proxy.safeAreaInsets.leading + 16))
                    .padding(.top, max(14, proxy.safeAreaInsets.top + 7))
                    .padding(.bottom, max(14, proxy.safeAreaInsets.bottom + 7))
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.66)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.24), value: controlsVisible)
            .onAppear { scheduleHide() }
            .onDisappear { hideTask?.cancel() }
        }
        .onChange(of: volume) { _, value in playback.setVolume(value) }
        .onChange(of: isMuted) { _, value in playback.setMuted(value) }
    }

    private var topBar: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    LivePulse(color: .auroraMint, size: 7, animated: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stream.name)
                            .font(.auroraLabel(12, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("TRUYỀN HÌNH TRỰC TIẾP")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .auroraSmoke(in: Capsule(), strength: 0.4)

                Spacer()

                Button { playback.syncToLiveEdge(); scheduleHide() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(.white)
                .auroraSmoke(strength: 0.4)
                .accessibilityLabel("Đồng bộ về thời gian phát trực tiếp")

                quickControl(icon: "rectangle.on.rectangle", title: "Tỷ lệ", value: videoFit.rawValue)
                pipButton

                Button { isFullscreen = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(.white)
                .auroraSmoke(strength: 0.4)
                .accessibilityLabel("Đóng trình phát")
            }
            if quickMenu != nil { quickMenuPanel }
        }
    }

    private func quickControl(icon: String, title: String, value: String) -> some View {
        Button {
            withAnimation(Motion.sheet) {
                quickMenu = quickMenu == .videoFit ? nil : .videoFit
                volumePopoverOpen = false
            }
            scheduleHide()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(value).font(.system(size: 9, weight: .black, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(quickMenu == .videoFit ? Color.auroraVoid : .white)
            .frame(width: 54, height: 44)
            .background {
                if quickMenu == .videoFit {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).fill(LinearGradient.auroraPrimary)
                } else {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.black.opacity(0.42))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(quickMenu == .videoFit ? 0.32 : 0.16), lineWidth: 0.8)
            }
        }
        .buttonStyle(.auroraPress(scale: 0.92))
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var quickMenuPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("TỶ LỆ KHUNG HÌNH")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.auroraViolet)
                Spacer(minLength: 20)
                Button {
                    withAnimation(Motion.sheet) { quickMenu = nil }
                    scheduleHide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng lựa chọn")
            }
            ForEach(TVVideoFit.allCases) { fit in
                Button {
                    withAnimation(Motion.tap) { videoFit = fit }
                    withAnimation(Motion.sheet) { quickMenu = nil }
                    scheduleHide()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: fit == videoFit ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(fit == videoFit ? Color.auroraViolet : .white.opacity(0.45))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fit.rawValue)
                                .font(.auroraLabel(12, weight: .bold))
                                .foregroundStyle(.white)
                            Text(fit == .fit ? "Giữ nguyên khung hình" : fit == .fill ? "Lấp đầy màn hình" : "Phóng phủ toàn màn hình")
                                .font(.auroraBody(9))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 42)
                    .background(
                        fit == videoFit ? Color.auroraViolet.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
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

    private var pipButton: some View {
        Group {
            if pipCoordinator.isSupported {
                Button {
                    pipCoordinator.isActive ? pipCoordinator.stop() : pipCoordinator.start()
                    scheduleHide()
                } label: {
                    Image(systemName: pipCoordinator.isActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(pipCoordinator.isActive ? Color.auroraVoid : .white)
                .background {
                    Circle().fill(pipCoordinator.isActive ? AnyShapeStyle(LinearGradient.auroraPrimary) : AnyShapeStyle(Color.black.opacity(0.42)))
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                }
                .accessibilityLabel(pipCoordinator.isActive ? "Thoát Picture-in-Picture" : "Bật Picture-in-Picture")
            }
        }
    }

    private var centerControls: some View {
        Button {
            playback.togglePlayback()
            scheduleHide()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Color.auroraVoid)
                .frame(width: 74, height: 74)
                .background(Circle().fill(LinearGradient.auroraPrimary))
                .auroraHalo(.auroraViolet, radius: 26, opacity: 0.55)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.auroraPress(scale: 0.9))
        .accessibilityLabel(playback.isPlaying ? "Tạm dừng" : "Phát")
    }

    private var bottomControls: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    LivePulse(color: .auroraMint, size: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.auroraMint.opacity(0.2)))
                .overlay(Capsule().strokeBorder(Color.auroraMint.opacity(0.4), lineWidth: 0.8))

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16)).frame(height: 4)
                    Capsule().fill(LinearGradient.auroraCool).frame(height: 4)
                }
                .frame(maxWidth: .infinity)
                .auroraHalo(.auroraMint, radius: 10, opacity: 0.4)

                Button {
                    withAnimation(Motion.sheet) { volumePopoverOpen.toggle() }
                    scheduleHide()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
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
                        Button { isMuted.toggle() } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        Slider(value: $volume, in: 0...1, onEditingChanged: { editing in if !editing { scheduleHide() } })
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
                Text("CINEMORA LIVE")
                    .font(.auroraBody(9))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(stream.name)
                    .font(.auroraLabel(9, weight: .bold))
                    .foregroundStyle(Color.auroraViolet)
                    .lineLimit(1)
            }
        }
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.2)) {
            controlsVisible.toggle()
            if !controlsVisible { volumePopoverOpen = false }
        }
        if controlsVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                controlsVisible = false
                volumePopoverOpen = false
            }
        }
    }
}

private struct TVFullscreenPlayer: View {
    let stream: TvStream
    @ObservedObject var playback: TVPlaybackController
    let pipCoordinator: PictureInPictureCoordinator
    @Binding var isMuted: Bool
    @Binding var volume: Double
    @Binding var isFullscreen: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVPlayerView(stream: stream, playback: playback, pipCoordinator: pipCoordinator, isMuted: $isMuted, volume: $volume, isFullscreen: $isFullscreen).ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if let url = stream.streamURL {
                playback.load(url, audioURL: stream.audioURL)
                playback.setVolume(volume)
                playback.setMuted(isMuted)
            }
            forceLandscape()
        }
        .onDisappear {
            if pipCoordinator.isActive { pipCoordinator.stop() }
            playback.shutdown()
            forcePortrait()
        }
    }

    private func forceLandscape() { forceOrientation(.landscapeRight) }
    private func forcePortrait() { forceOrientation(.portrait) }

    private func forceOrientation(_ orientation: UIInterfaceOrientation) {
        let isLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        // See the player: the KVC orientation hack is gone.
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
}

// MARK: - Posted video row

private struct TVVideoRow: View {
    let video: TvVideo
    let action: () -> Void
    @State private var pulse = false

    private var isFeatured: Bool { video.isFeatured == true }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                PosterArt(url: video.logoURL)
                    .frame(width: 88, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.8)
                    }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(video.name)
                            .font(.auroraLabel(14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isFeatured {
                            Text("NỔI BẬT")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundStyle(Color.auroraVoid)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(LinearGradient.auroraPrimary))
                        }
                    }
                    Text(video.episodes.count > 1 ? "Video bộ · \(video.episodes.count) tập" : "Video · sẵn sàng phát")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(LinearGradient.auroraPrimary)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: isFeatured)
            }
            .padding(13)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.auroraPress(scale: 0.98))
        .auroraCard(cornerRadius: 20, tint: isFeatured ? .auroraViolet : .auroraSky, glow: isFeatured, fill: isFeatured ? 1 : 0.6)
        .scaleEffect(isFeatured && video.featuredEffect == "pulse" && pulse ? 1.015 : 1)
        .overlay(alignment: .topTrailing) {
            if isFeatured && video.featuredEffect == "ribbon" {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.auroraVoid)
                    .padding(7)
                    .background(Circle().fill(LinearGradient.auroraPrimary))
                    .offset(x: -9, y: 9)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            if isFeatured && video.featuredEffect == "pulse" {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

// MARK: - Posted video fullscreen player

private struct TVVideoFullscreenPlayer: View {
    let video: TvVideo
    @Binding var episodeIndex: Int
    @ObservedObject var playback: TVPlaybackController
    let pipCoordinator: PictureInPictureCoordinator
    @Binding var isMuted: Bool
    @Binding var volume: Double
    @Binding var isPresented: Bool
    @StateObject private var subtitles = SubtitleController()
    @State private var subtitlePreferences = SubtitlePreferences()
    @State private var controlsVisible = true
    @State private var locked = false
    @State private var fit: TVVideoFit = .fit
    @State private var qualityIndex = 0
    @State private var settingsOpen = false
    @State private var advancedSettings = false
    @State private var autoNext = true
    @State private var stopTimer: TVStopTimer = .off
    @State private var stopAtEpisode = false
    @State private var stopAtEpisodeIndex = 0
    @State private var stopTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    private enum TVStopTimer: String, CaseIterable, Identifiable {
        case off = "Tắt", fifteen = "15 phút", thirty = "30 phút", sixty = "60 phút"
        var id: String { rawValue }
        var seconds: Double? { switch self { case .off: return nil; case .fifteen: return 900; case .thirty: return 1800; case .sixty: return 3600 } }
    }
    private var episode: TvVideoEpisode? { video.episodes.indices.contains(episodeIndex) ? video.episodes[episodeIndex] : nil }
    private var quality: TvVideoQuality? {
        guard let episode, episode.qualities.indices.contains(qualityIndex) else { return nil }
        return episode.qualities[qualityIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVNativeVideoSurface(player: playback.player, fit: fit, pipCoordinator: pipCoordinator).ignoresSafeArea()
            if subtitlePreferences.enabled, let text = subtitles.currentText {
                VStack {
                    Spacer()
                    Text(text)
                        .font(subtitlePreferences.font)
                        .foregroundStyle(subtitlePreferences.textColor)
                        .multilineTextAlignment(subtitlePreferences.textAlignment)
                        .frame(maxWidth: .infinity, alignment: subtitlePreferences.textAlignment == .leading ? .leading : subtitlePreferences.textAlignment == .trailing ? .trailing : .center)
                        .padding(.horizontal, 24)
                        .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0)
                        .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0)
                        .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: subtitlePreferences.outlineWidth)
                        .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: -subtitlePreferences.outlineWidth)
                        .padding(.bottom, 36)
                }
                .allowsHitTesting(false)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture {
                guard !locked, !settingsOpen else { return }
                withAnimation { controlsVisible.toggle() }
                if controlsVisible { scheduleHide() }
            }
            if controlsVisible && !settingsOpen { playerControls }
            if locked {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            locked = false
                            controlsVisible = true
                            scheduleHide()
                        } label: {
                            Image(systemName: "lock.fill")
                                .frame(width: 50, height: 50)
                                .background(Color.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.auroraPress(scale: 0.9))
                        .foregroundStyle(.white)
                        .padding(22)
                    }
                }
                .transition(.opacity)
            }
            if settingsOpen {
                settingsOverlay
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.84, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity)
                    ))
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { loadCurrent(); scheduleHide() }
        .animation(Motion.sheet, value: settingsOpen)
        .animation(.easeOut(duration: 0.26), value: advancedSettings)
        .onDisappear { hideTask?.cancel(); stopTask?.cancel(); playback.shutdown() }
        .onChange(of: episodeIndex) { _, _ in qualityIndex = 0; loadCurrent() }
        .onChange(of: playback.currentTime) { _, time in subtitles.update(time: time, bilingual: subtitlePreferences.bilingual) }
        .onChange(of: stopTimer) { _, _ in scheduleStop() }
        .onChange(of: stopAtEpisode) { _, _ in scheduleStop() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === playback.player.currentItem else { return }
            if stopAtEpisode && episodeIndex == stopAtEpisodeIndex { playback.pause() }
            else if autoNext { moveEpisode(1) } else { playback.pause() }
        }
    }

    private var playerControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { isPresented = false } label: {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .auroraSmoke(strength: 0.4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(video.name).font(.auroraLabel(13, weight: .bold))
                    Text(episode?.name ?? "Video")
                        .font(.auroraBody(9))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)

                Spacer()

                Button {
                    withAnimation(Motion.sheet) { settingsOpen = true; advancedSettings = false }
                    hideTask?.cancel()
                } label: {
                    Image(systemName: "gearshape.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .foregroundStyle(Color.auroraVoid)
                .background(Circle().fill(LinearGradient.auroraPrimary))
                .auroraHalo(.auroraViolet, radius: 16, opacity: 0.45)
                .accessibilityLabel("Cài đặt video")

                Button {
                    locked = true
                    controlsVisible = false
                } label: {
                    Image(systemName: "lock.open").frame(width: 44, height: 44)
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                .auroraSmoke(strength: 0.4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Spacer()

            if playback.isLoading { ProgressView().tint(.white) }

            HStack(spacing: 30) {
                Button { skip(-10) } label: { skipButton("gobackward.10") }
                    .buttonStyle(.auroraPress(scale: 0.9))
                Button {
                    playback.togglePlayback()
                    scheduleHide()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .black))
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(LinearGradient.auroraPrimary))
                        .foregroundStyle(Color.auroraVoid)
                        .auroraHalo(.auroraViolet, radius: 24, opacity: 0.5)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.auroraPress(scale: 0.9))
                Button { skip(10) } label: { skipButton("goforward.10") }
                    .buttonStyle(.auroraPress(scale: 0.9))
            }
            .foregroundStyle(.white)

            Spacer()

            HStack {
                if video.episodes.count > 1 {
                    Button { moveEpisode(-1) } label: {
                        Label("Tập trước", systemImage: "backward.end")
                            .font(.auroraLabel(11, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.auroraPress(scale: 0.94))
                    .auroraSmoke(in: Capsule(), strength: 0.35)

                    Spacer()

                    Button { moveEpisode(1) } label: {
                        Label("Tập tiếp", systemImage: "forward.end")
                            .font(.auroraLabel(11, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.auroraPress(scale: 0.94))
                    .auroraSmoke(in: Capsule(), strength: 0.35)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func skipButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .auroraSmoke(strength: 0.5)
    }

    private var settingsOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture {
                    withAnimation(Motion.sheet) { settingsOpen = false }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "gearshape.fill").foregroundStyle(Color.auroraViolet)
                        Text("Cài đặt video").font(.auroraDisplay(18))
                        Spacer()
                        Button { withAnimation(Motion.sheet) { settingsOpen = false } } label: {
                            Image(systemName: "xmark")
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("QUICK CONTROLS")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Color.auroraViolet)
                    Toggle(isOn: $subtitlePreferences.enabled) { Label("Phụ đề", systemImage: "captions.bubble.fill") }
                        .tint(Color.auroraViolet)
                    Toggle(isOn: $autoNext) { Label("Tự động chuyển tập", systemImage: "forward.end.fill") }
                        .tint(Color.auroraViolet)
                    Toggle(isOn: $stopAtEpisode) { Label("Dừng ở tập đã chọn", systemImage: "stop.circle.fill") }
                        .tint(Color.auroraViolet)
                    if stopAtEpisode {
                        Picker("Tập dừng", selection: $stopAtEpisodeIndex) {
                            ForEach(video.episodes.indices, id: \.self) { index in
                                Text(video.episodes[index].name).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.auroraViolet)
                    }
                    HStack {
                        Label("Tự dừng phát", systemImage: "moon.zzz.fill")
                        Spacer()
                        Picker("Tự dừng", selection: $stopTimer) {
                            ForEach(TVStopTimer.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Color.auroraViolet)
                    }
                    Divider().overlay(Color.white.opacity(0.14))
                    Button {
                        withAnimation(Motion.sheet) { advancedSettings.toggle() }
                    } label: {
                        HStack {
                            Label("Advanced Settings", systemImage: "slider.horizontal.3")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(advancedSettings ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    if advancedSettings {
                        subtitlePreview
                        ScrollView(.vertical, showsIndicators: false) {
                            SubtitlePreferencesEditor(preferences: $subtitlePreferences, compact: true)
                        }
                        .frame(maxHeight: 330)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(width: min(390, max(300, proxy.size.width - 24)), alignment: .topLeading)
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
                .padding(.top, max(14, proxy.safeAreaInsets.top + 8))
                .padding(.trailing, max(14, proxy.safeAreaInsets.trailing + 10))
                .padding(.bottom, max(14, proxy.safeAreaInsets.bottom + 8))
            }
        }
        .ignoresSafeArea()
    }

    private var subtitlePreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("XEM TRƯỚC REALTIME")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.auroraViolet)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color.auroraSky.opacity(0.4), .black.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 96)
                Text(subtitlePreferences.bilingual ? "Đây là phụ đề xem trước\nThis is a bilingual preview" : "Đây là phụ đề xem trước")
                    .font(subtitlePreferences.font)
                    .foregroundStyle(subtitlePreferences.textColor)
                    .multilineTextAlignment(subtitlePreferences.textAlignment)
                    .frame(maxWidth: .infinity, alignment: subtitlePreferences.textAlignment == .leading ? .leading : subtitlePreferences.textAlignment == .trailing ? .trailing : .center)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: subtitlePreferences.outlineWidth)
                    .shadow(color: subtitlePreferences.outlineColor, radius: 0, x: 0, y: -subtitlePreferences.outlineWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func loadCurrent() {
        guard let episode, episode.qualities.indices.contains(qualityIndex), let quality, let url = quality.streamURL else { return }
        playback.load(url)
        playback.setVolume(volume)
        playback.setMuted(isMuted)
        subtitles.load(url: quality.subtitleURL ?? quality.languageSubtitleTracks.first?.subtitleURL ?? episode.subtitleURL, bilingualURL: quality.bilingualSubtitleURL ?? episode.bilingualSubtitleURL)
    }

    private func moveEpisode(_ offset: Int) {
        let next = episodeIndex + offset
        guard video.episodes.indices.contains(next) else { playback.togglePlayback(); return }
        episodeIndex = next
    }

    private func skip(_ seconds: Double) {
        let now = playback.player.currentTime().seconds
        playback.player.seek(to: CMTime(seconds: max(0, now + seconds), preferredTimescale: 600))
    }

    private func scheduleStop() {
        stopTask?.cancel()
        guard let seconds = stopTimer.seconds else { return }
        stopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            playback.pause()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { controlsVisible = false }
        }
    }
}

// MARK: - Live stream row (legacy list style)

private struct TVStreamRow: View {
    let stream: TvStream
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                PosterArt(url: stream.posterURL)
                    .frame(width: 84, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(stream.name)
                        .font(.auroraLabel(14, weight: .bold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        LivePulse(color: stream.isOnline ? .auroraMint : .auroraAmber, size: 6)
                        Text(stream.isOnline ? "Trực tiếp" : "Nguồn chưa ổn định")
                            .font(.auroraBody(11))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "play.circle.fill" : "play.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.auroraViolet : .white.opacity(0.55))
            }
            .padding(13)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.auroraPress(scale: 0.98))
        .auroraCard(cornerRadius: 20, tint: isSelected ? .auroraViolet : .auroraSky, glow: isSelected, fill: isSelected ? 1 : 0.55)
    }
}

private final class TVPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct TVNativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let fit: TVVideoFit
    let pipCoordinator: PictureInPictureCoordinator
    func makeUIView(context: Context) -> TVPlayerLayerView {
        let view = TVPlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fit.gravity
        pipCoordinator.attach(to: view.playerLayer)
        return view
    }
    func updateUIView(_ view: TVPlayerLayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fit.gravity
        pipCoordinator.attach(to: view.playerLayer)
    }
}

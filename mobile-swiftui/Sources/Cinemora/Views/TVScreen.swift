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
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay { self.isLoading = false }
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
                syncToLiveEdge()
            }
        }
    }

    private func handleAudioRouteChange() {
        configureAudioSession()
        guard !userPaused, currentURL != nil else { return }
        if hasSeparateAudio && (separateAudioPlayer.rate == 0 || player.rate == 0) { syncToLiveEdge() }
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
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = TVPlaybackController()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @State private var selectedStreamID: Int?
    @State private var selectedVideoID: Int?
    @State private var selectedVideoEpisode = 0
    @State private var isMuted = false
    @State private var volume = 1.0
    @State private var isPlayerPresented = false

    private var selectedStream: TvStream? {
        guard let selectedStreamID else { return nil }
        return store.tvStreams.first { $0.id == selectedStreamID }
    }

    private var selectedVideo: TvVideo? {
        guard let selectedVideoID else { return nil }
        return store.tvVideos.first { $0.id == selectedVideoID }
    }

    /// Posted TV videos use the same movie player as catalog movies. Each
    /// quality is represented as a source, while all sources expose the same
    /// episode list. This keeps the player UI and playback behavior in one
    /// place instead of maintaining a second, less capable video player.
    private var selectedVideoMovie: Movie? {
        selectedVideo?.asPlayerMovie
    }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "CINEMORA LIVE", title: "TRUYỀN HÌNH")
                    if store.tvLoading && store.tvStreams.isEmpty {
                        ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding(.top, 70)
                    } else if store.tvStreams.isEmpty {
                        StateMessage(icon: "tv", title: "Chưa có kênh truyền hình", detail: store.tvError ?? "Admin chưa thêm stream nào.")
                    } else {
                        SectionHeading(eyebrow: "KÊNH TRỰC TUYẾN", title: "Chọn kênh để xem")
                        LazyVStack(spacing: 10) {
                            ForEach(store.tvStreams) { stream in
                                TVStreamRow(stream: stream, isSelected: stream.id == selectedStream?.id) {
                                    selectedStreamID = stream.id
                                    play(stream)
                                    isPlayerPresented = true
                                }
                            }
                        }
                    }
                    if !store.tvVideos.isEmpty {
                        SectionHeading(eyebrow: "VIDEO", title: "Video đã đăng")
                        LazyVStack(spacing: 10) {
                            ForEach(store.tvVideos) { video in
                                TVVideoRow(video: video) {
                                    selectedVideoID = video.id
                                    selectedVideoEpisode = 0
                                    selectedStreamID = nil
                                    isPlayerPresented = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 36)
            }
            .refreshable { await store.refreshTvStreams() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.startTvLiveUpdates() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshTvStreams() } }
        }
        .onChange(of: store.tvStreams) { _, streams in
            if selectedStreamID == nil { selectedStreamID = streams.first?.id }
            else if !streams.contains(where: { $0.id == selectedStreamID }) { selectedStreamID = streams.first?.id }
        }
        .onChange(of: isPlayerPresented) { _, presented in
            if !presented {
                if pipCoordinator.isActive { pipCoordinator.stop() }
                playback.shutdown()
            }
        }
        .onDisappear { playback.shutdown(); store.stopTvLiveUpdates() }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            if let selectedStream {
                TVFullscreenPlayer(stream: selectedStream, playback: playback, pipCoordinator: pipCoordinator, isMuted: $isMuted, volume: $volume, isFullscreen: $isPlayerPresented)
            } else if let selectedVideoMovie {
                CinemaPlayerScreen(movie: selectedVideoMovie, servers: selectedVideoMovie.availableServers, initialServer: 0, initialEpisode: selectedVideoEpisode, subtitleCustomizationEnabled: true)
            }
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
                    subtitleUrl: (quality.subtitleURL ?? tvEpisode.subtitleURL)?.absoluteString,
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
                        if playback.isLoading { ProgressView("Đang tải nguồn phát…").tint(.white).foregroundStyle(.white).padding(18).cinemaGlass(in: Capsule(), tint: .black.opacity(0.42)) }
                        Spacer()
                        centerControls
                        Spacer()
                        bottomControls
                    }
                    .padding(.horizontal, max(18, proxy.safeAreaInsets.leading + 16))
                    .padding(.top, max(14, proxy.safeAreaInsets.top + 7))
                    .padding(.bottom, max(14, proxy.safeAreaInsets.bottom + 7))
                    .background(LinearGradient(colors: [.black.opacity(0.58), .clear, .clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controlsVisible)
            .onAppear { scheduleHide() }
            .onDisappear { hideTask?.cancel() }
        }
        .onChange(of: volume) { _, value in playback.setVolume(value) }
        .onChange(of: isMuted) { _, value in playback.setMuted(value) }
    }

    private var topBar: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "tv.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stream.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        Text("TRUYỀN HÌNH TRỰC TIẾP").font(.system(size: 8, weight: .black, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.58))
                    }
                }
                .padding(.horizontal, 12).frame(height: 42)
                .background(.black.opacity(0.36), in: Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
                Spacer()
                Button { playback.syncToLiveEdge(); scheduleHide() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.plain).foregroundStyle(.white).cinemaGlass(in: Circle(), tint: .black.opacity(0.36))
                .accessibilityLabel("Đồng bộ về thời gian phát trực tiếp")
                quickControl(icon: "rectangle.on.rectangle", title: "Tỷ lệ", value: videoFit.rawValue)
                pipButton
                Button { isFullscreen = false } label: { Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).frame(width: 42, height: 42) }
                    .buttonStyle(.plain).foregroundStyle(.white).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Đóng trình phát")
            }
            if quickMenu != nil { quickMenuPanel }
        }
    }

    private func quickControl(icon: String, title: String, value: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { quickMenu = quickMenu == .videoFit ? nil : .videoFit; volumePopoverOpen = false }
            scheduleHide()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(value).font(.system(size: 9, weight: .black, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(quickMenu == .videoFit ? Color.cinemaInk : .white)
            .frame(width: 52, height: 42)
            .background(quickMenu == .videoFit ? Color.cinemaAccent : Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(quickMenu == .videoFit ? 0.35 : 0.14), lineWidth: 0.8))
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value)
    }

    private var quickMenuPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TỶ LỆ KHUNG HÌNH").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1.2).foregroundStyle(Color.cinemaAccent)
                Spacer(minLength: 20)
                Button { withAnimation(.easeOut(duration: 0.18)) { quickMenu = nil }; scheduleHide() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 24, height: 24)
                }.buttonStyle(.plain)
            }
            ForEach(TVVideoFit.allCases) { fit in
                Button {
                    videoFit = fit
                    withAnimation(.easeOut(duration: 0.18)) { quickMenu = nil }
                    scheduleHide()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: fit == videoFit ? "checkmark.circle.fill" : "circle").font(.system(size: 16, weight: .semibold)).foregroundStyle(fit == videoFit ? Color.cinemaAccent : .white.opacity(0.45))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fit.rawValue).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text(fit == .fit ? "Giữ nguyên khung hình" : fit == .fill ? "Lấp đầy màn hình" : "Phóng phủ toàn màn hình").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.52))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(fit == videoFit ? Color.cinemaAccent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
        .padding(12).frame(width: 260)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
    }

    private var pipButton: some View {
        Group {
            if pipCoordinator.isSupported {
                Button { pipCoordinator.isActive ? pipCoordinator.stop() : pipCoordinator.start(); scheduleHide() } label: {
                    Image(systemName: pipCoordinator.isActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(pipCoordinator.isActive ? Color.cinemaInk : .white)
                .background(pipCoordinator.isActive ? Color.cinemaAccent : Color.black.opacity(0.36), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
                .accessibilityLabel(pipCoordinator.isActive ? "Thoát Picture-in-Picture" : "Bật Picture-in-Picture")
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 38) {
            Button { playback.togglePlayback(); scheduleHide() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .black)).foregroundStyle(Color.cinemaInk)
                    .frame(width: 70, height: 70).background(Color.cinemaAccent, in: Circle())
                    .shadow(color: Color.cinemaAccent.opacity(0.24), radius: 22, y: 8)
            }
            .buttonStyle(.plain).accessibilityLabel(playback.isPlaying ? "Tạm dừng" : "Phát")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("LIVE").font(.system(size: 10, weight: .black, design: .rounded)).foregroundStyle(Color.cinemaAccent).padding(.horizontal, 8).frame(height: 28).background(Color.cinemaAccent.opacity(0.14), in: Capsule())
                Capsule().fill(Color.cinemaAccent).frame(height: 3)
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { volumePopoverOpen.toggle() }; scheduleHide() } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 43, height: 43)
                }
                .buttonStyle(.plain).cinemaGlass(in: Circle(), tint: .black.opacity(0.4)).accessibilityLabel("Điều chỉnh âm lượng")
            }
            .overlay(alignment: .bottomTrailing) {
                if volumePopoverOpen {
                    HStack(spacing: 10) {
                        Button { isMuted.toggle() } label: { Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 34, height: 34) }.buttonStyle(.plain)
                        Slider(value: $volume, in: 0...1, onEditingChanged: { editing in if !editing { scheduleHide() } }).tint(Color.cinemaAccent).frame(width: 142)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.7)).offset(y: -49)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
                }
            }
            HStack { Text("CINEMORA LIVE").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.56)); Spacer(); Text(stream.name).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.cinemaAccent).lineLimit(1) }
        }
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible.toggle(); if !controlsVisible { volumePopoverOpen = false } }
        if controlsVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false; volumePopoverOpen = false }
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
        .onAppear { forceLandscape() }
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
}

private struct TVVideoRow: View {
    let video: TvVideo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                PosterArt(url: video.logoURL).frame(width: 76, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.name).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    Text(video.episodes.count > 1 ? "Video bộ · \(video.episodes.count) tập" : "Video · sẵn sàng phát")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(Color.cinemaAccent)
            }
            .padding(13)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

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
                VStack { Spacer(); Text(text).font(subtitlePreferences.font).foregroundStyle(subtitlePreferences.textColor).multilineTextAlignment(subtitlePreferences.textAlignment).frame(maxWidth: .infinity, alignment: subtitlePreferences.textAlignment == .leading ? .leading : subtitlePreferences.textAlignment == .trailing ? .trailing : .center).padding(.horizontal, 24).padding(.vertical, 6).background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 7)).shadow(color: subtitlePreferences.outlineColor, radius: 0, x: subtitlePreferences.outlineWidth, y: 0).shadow(color: subtitlePreferences.outlineColor, radius: 0, x: -subtitlePreferences.outlineWidth, y: 0).padding(.bottom, 36) }.allowsHitTesting(false)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture { guard !locked, !settingsOpen else { return }; withAnimation { controlsVisible.toggle() }; if controlsVisible { scheduleHide() } }
            if controlsVisible && !settingsOpen { playerControls }
            if locked { VStack { Spacer(); HStack { Spacer(); Button { locked = false; controlsVisible = true; scheduleHide() } label: { Image(systemName: "lock.fill").frame(width: 48, height: 48).background(.black.opacity(0.48), in: Circle()) }.buttonStyle(.plain).foregroundStyle(.white).padding(22) } }.transition(.opacity) }
            if settingsOpen { settingsOverlay.transition(.move(edge: .trailing).combined(with: .opacity)).zIndex(10) }
        }
        .preferredColorScheme(.dark).statusBarHidden(true).persistentSystemOverlays(.hidden)
        .onAppear { loadCurrent(); scheduleHide() }
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
            HStack(spacing: 9) {
                Button { isPresented = false } label: { Image(systemName: "chevron.down").frame(width: 42, height: 42) }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) { Text(video.name).font(.system(size: 13, weight: .bold)); Text(episode?.name ?? "Video").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)) }.lineLimit(1)
                Spacer()
                Button { withAnimation { settingsOpen = true }; hideTask?.cancel() } label: { Image(systemName: "gearshape.fill").frame(width: 42, height: 42) }.buttonStyle(.plain).foregroundStyle(Color.cinemaInk).background(Color.cinemaAccent, in: Circle()).accessibilityLabel("Cài đặt video")
                Button { locked = true; controlsVisible = false } label: { Image(systemName: "lock.open").frame(width: 42, height: 42) }.buttonStyle(.plain)
            }.foregroundStyle(.white).padding(.horizontal, 14).padding(.top, 12)
            Spacer()
            if playback.isLoading { ProgressView().tint(.white) }
            HStack(spacing: 28) {
                Button { skip(-10) } label: { Image(systemName: "gobackward.10").font(.system(size: 22)) }.buttonStyle(.plain)
                Button { playback.togglePlayback(); scheduleHide() } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28)).frame(width: 68, height: 68).background(Color.cinemaAccent, in: Circle()).foregroundStyle(Color.cinemaInk) }.buttonStyle(.plain)
                Button { skip(10) } label: { Image(systemName: "goforward.10").font(.system(size: 22)) }.buttonStyle(.plain)
            }.foregroundStyle(.white)
            Spacer()
            HStack { if video.episodes.count > 1 { Button { moveEpisode(-1) } label: { Label("Tập trước", systemImage: "backward.end") }.buttonStyle(.plain); Spacer(); Button { moveEpisode(1) } label: { Label("Tập tiếp", systemImage: "forward.end") }.buttonStyle(.plain) } }.font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 16).padding(.bottom, 18)
        }.background(LinearGradient(colors: [.black.opacity(0.68), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var settingsOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { withAnimation { settingsOpen = false } }
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Image(systemName: "gearshape.fill").foregroundStyle(Color.cinemaAccent); Text("Cài đặt video").font(.system(size: 18, weight: .black, design: .rounded)); Spacer(); Button { withAnimation { settingsOpen = false } } label: { Image(systemName: "xmark").frame(width: 30, height: 30).background(.white.opacity(0.08), in: Circle()) }.buttonStyle(.plain) }
                    Text("QUICK CONTROLS").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1).foregroundStyle(Color.cinemaAccent)
                    Toggle(isOn: $subtitlePreferences.enabled) { Label("Phụ đề", systemImage: "captions.bubble.fill") }.tint(Color.cinemaAccent)
                    Toggle(isOn: $autoNext) { Label("Tự động chuyển tập", systemImage: "forward.end.fill") }.tint(Color.cinemaAccent)
                    Toggle(isOn: $stopAtEpisode) { Label("Dừng ở tập đã chọn", systemImage: "stop.circle.fill") }.tint(Color.cinemaAccent)
                    if stopAtEpisode { Picker("Tập dừng", selection: $stopAtEpisodeIndex) { ForEach(video.episodes.indices, id: \.self) { index in Text(video.episodes[index].name).tag(index) } }.pickerStyle(.menu).tint(Color.cinemaAccent) }
                    HStack { Label("Tự dừng phát", systemImage: "moon.zzz.fill"); Spacer(); Picker("Tự dừng", selection: $stopTimer) { ForEach(TVStopTimer.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.menu).tint(Color.cinemaAccent) }
                    Divider().overlay(.white.opacity(0.15))
                    Button { withAnimation { advancedSettings.toggle() } } label: { HStack { Label("Advanced Settings", systemImage: "slider.horizontal.3"); Spacer(); Image(systemName: advancedSettings ? "chevron.up" : "chevron.down") } }.buttonStyle(.plain).foregroundStyle(.white)
                    if advancedSettings { ScrollView(.vertical, showsIndicators: false) { SubtitlePreferencesEditor(preferences: $subtitlePreferences, compact: true) }.frame(maxHeight: 330) }
                }.foregroundStyle(.white).padding(18).frame(width: min(380, max(300, proxy.size.width - 24)), alignment: .topLeading).frame(maxHeight: .infinity, alignment: .topLeading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.2), lineWidth: 0.8)).shadow(color: .black.opacity(0.45), radius: 28, x: -8, y: 12).padding(.top, max(14, proxy.safeAreaInsets.top + 8)).padding(.trailing, max(14, proxy.safeAreaInsets.trailing + 10)).padding(.bottom, max(14, proxy.safeAreaInsets.bottom + 8))
            }
        }.ignoresSafeArea()
    }

    private func loadCurrent() {
        guard let episode, episode.qualities.indices.contains(qualityIndex), let quality, let url = quality.streamURL else { return }
        playback.load(url); playback.setVolume(volume); playback.setMuted(isMuted)
        subtitles.load(url: quality.subtitleURL ?? episode.subtitleURL, bilingualURL: quality.bilingualSubtitleURL ?? episode.bilingualSubtitleURL)
    }
    private func moveEpisode(_ offset: Int) { let next = episodeIndex + offset; guard video.episodes.indices.contains(next) else { playback.togglePlayback(); return }; episodeIndex = next }
    private func skip(_ seconds: Double) { let now = playback.player.currentTime().seconds; playback.player.seek(to: CMTime(seconds: max(0, now + seconds), preferredTimescale: 600)) }
    private func scheduleStop() { stopTask?.cancel(); guard let seconds = stopTimer.seconds else { return }; stopTask = Task { @MainActor in try? await Task.sleep(for: .seconds(seconds)); guard !Task.isCancelled else { return }; playback.pause() } }
    private func scheduleHide() { hideTask?.cancel(); hideTask = Task { @MainActor in try? await Task.sleep(for: .seconds(4)); guard !Task.isCancelled else { return }; withAnimation { controlsVisible = false } } }
}

private struct TVStreamRow: View {
    let stream: TvStream
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                PosterArt(url: stream.posterURL)
                    .frame(width: 76, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(stream.name).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    HStack(spacing: 5) { Circle().fill(stream.isOnline ? .green : .orange).frame(width: 6, height: 6); Text(stream.isOnline ? "Trực tiếp" : "Nguồn chưa ổn định") }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: isSelected ? "play.circle.fill" : "play.circle").font(.system(size: 24)).foregroundStyle(isSelected ? Color.cinemaAccent : .white.opacity(0.55))
            }
            .padding(13)
            .background(isSelected ? Color.cinemaAccent.opacity(0.14) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(isSelected ? Color.cinemaAccent.opacity(0.55) : .white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
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
        let view = TVPlayerLayerView(); view.backgroundColor = .black; view.playerLayer.player = player; view.playerLayer.videoGravity = fit.gravity
        pipCoordinator.attach(to: view.playerLayer); return view
    }
    func updateUIView(_ view: TVPlayerLayerView, context: Context) {
        view.playerLayer.player = player; view.playerLayer.videoGravity = fit.gravity; pipCoordinator.attach(to: view.playerLayer)
    }
}

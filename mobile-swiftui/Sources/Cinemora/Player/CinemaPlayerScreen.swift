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
    @Published var playbackRate: Float = 1
    @Published var errorMessage: String?
    @Published var activeURL: URL?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var activeRequestID = UUID()

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                if time.seconds.isFinite { self.currentTime = time.seconds }
                if let item = self.player.currentItem, item.duration.seconds.isFinite { self.duration = item.duration.seconds }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    func shutdown() {
        loadTask?.cancel()
        loadTask = nil
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        itemObservation = nil
    }

    func load(_ episode: MovieEpisode, startAt: Double = 0) {
        loadTask?.cancel()
        activeRequestID = UUID()
        let requestID = activeRequestID
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
        item.preferredForwardBufferDuration = 8
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.activeRequestID == requestID else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadTask?.cancel(); self.errorMessage = nil; self.isLoading = false
                    if startAt > 0 { self.player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                case .failed:
                    self.loadTask?.cancel(); self.isLoading = false
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

    func togglePlayback() {
        if player.timeControlStatus == .playing { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
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
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = target
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self else { return }
            Task { @MainActor in
                let actual = self.player.currentTime().seconds
                guard actual.isFinite else { return }
                self.currentTime = actual
            }
        }
    }
}

@MainActor
struct CinemaPlayerScreen: View {
    let movie: Movie
    let servers: [MovieServer]
    let initialServer: Int
    let initialEpisode: Int
    let resumeSeconds: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = PlaybackController()
    @State private var serverIndex = 0
    @State private var episodeIndex = 0
    @State private var controlsVisible = true
    @State private var picker: PickerKind?
    @State private var volume = 1.0
    @State private var volumePopoverOpen = false
    @State private var controlsLocked = false
    @State private var lockIndicatorVisible = true
    @State private var videoFit: VideoFit = .fit
    @State private var isScrubbing = false
    @State private var scrubValue = 0.0
    @State private var hideTask: Task<Void, Never>?
    @State private var lockHideTask: Task<Void, Never>?
    private let api = CinemaAPI.shared

    private enum PickerKind: Equatable { case episodes, sources, fit, speed }
    fileprivate enum VideoFit: String, CaseIterable, Hashable { case fit = "Vừa", fill = "Đầy", cover = "Phủ" }
    private var server: MovieServer? { servers.indices.contains(serverIndex) ? servers[serverIndex] : nil }
    private var episodes: [MovieEpisode] { server?.episodes ?? [] }
    private var episode: MovieEpisode? { episodes.indices.contains(episodeIndex) ? episodes[episodeIndex] : nil }

    init(movie: Movie, servers: [MovieServer], initialServer: Int, initialEpisode: Int, resumeSeconds: Int = 0) {
        self.movie = movie
        self.servers = servers
        self.initialServer = initialServer
        self.initialEpisode = initialEpisode
        self.resumeSeconds = max(0, resumeSeconds)
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
                    PosterArt(url: movie.backdropURL).ignoresSafeArea()
                        .overlay(Color.black.opacity(playback.isLoading ? 0.28 : 0.05))
                    NativeVideoSurface(player: playback.player, fit: videoFit).ignoresSafeArea().opacity(playback.isLoading ? 0.12 : 1).accessibilityLabel("Đang phát \(movie.name)")
                    Color.clear.contentShape(Rectangle()).onTapGesture { if controlsLocked { controlsLocked = false; controlsVisible = true } else { toggleControls() } }
                } else if let embed = episode?.embedURL {
                    EmbedWebPlayer(url: embed).ignoresSafeArea()
                } else {
                    PosterArt(url: movie.backdropURL).ignoresSafeArea().overlay(Color.black.opacity(0.4))
                }

                if controlsVisible && !controlsLocked {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        if playback.isLoading {
                            VStack(spacing: 8) {
                                ProgressView().tint(.cinemaAccent).scaleEffect(1.15)
                                Text(resumeSeconds > 0 ? "Đang tiếp tục từ \(formatTime(Double(resumeSeconds)))…" : "Đang tải nguồn phát…")
                                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("Bạn có thể chờ trong giây lát").font(.system(size: 10)).foregroundStyle(.white.opacity(0.62))
                            }
                            .padding(.horizontal, 20).padding(.vertical, 16).cinemaGlass(in: RoundedRectangle(cornerRadius: 18), tint: .black.opacity(0.52))
                        }
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
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: picker != nil)
            .animation(.easeInOut(duration: 0.2), value: controlsVisible)
            .onChange(of: episodeIndex) { _, _ in loadCurrentEpisode() }
            .onChange(of: serverIndex) { _, _ in
                if episodeIndex != 0 { episodeIndex = 0 }
                else { loadCurrentEpisode() }
            }
            .onChange(of: playback.isPlaying) { _, isPlaying in if isPlaying { scheduleHide() } }
            .onAppear { loadCurrentEpisode(); scheduleHide() }
            .onDisappear {
                hideTask?.cancel(); lockHideTask?.cancel()
                let watched = Int(playback.currentTime.rounded())
                let total = Int(playback.duration.rounded())
                let movieSnapshot = movie
                let episodeSnapshot = episode
                Task { try? await api.recordHistory(movie: movieSnapshot, episode: episodeSnapshot, sourceName: server?.name, watchedSeconds: watched, durationSeconds: total) }
                playback.shutdown()
            }
            .statusBarHidden(true)
        }
        .persistentSystemOverlays(.hidden)
    }

    private var topBar: some View {
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
            Button { withAnimation { picker = .fit }; controlsVisible = true } label: {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 42, height: 42)
            }
            .buttonStyle(.plain).contentShape(Circle()).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Tỷ lệ khung hình")
            Button { withAnimation { picker = .speed }; controlsVisible = true } label: {
                Image(systemName: "speedometer").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 42, height: 42)
            }
            .buttonStyle(.plain).contentShape(Circle()).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Tốc độ phát")
            Button { lockControls() } label: {
                Image(systemName: "lock").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
            }
            .foregroundStyle(.white).buttonStyle(.plain).cinemaGlass(in: Circle(), tint: .black.opacity(0.36)).accessibilityLabel("Khóa điều khiển")
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

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(formatTime(isScrubbing ? scrubValue : playback.currentTime)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).frame(width: 42, alignment: .leading)
                Slider(value: Binding(get: { isScrubbing ? scrubValue : min(max(0, playback.currentTime), max(1, playback.duration)) }, set: { value in if !isScrubbing { scrubValue = value }; scrubValue = value }), in: 0...max(1, playback.duration), onEditingChanged: { editing in if editing { scrubValue = min(max(0, playback.currentTime), max(1, playback.duration)); isScrubbing = true } else { playback.seek(to: scrubValue); isScrubbing = false; scheduleHide() } })
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

    private func pickerOverlay(_ kind: PickerKind) -> some View {
        ZStack {
            Color.black.opacity(0.63).ignoresSafeArea().onTapGesture { withAnimation { picker = nil }; scheduleHide() }
            VStack(spacing: 14) {
                Capsule().fill(.white.opacity(0.36)).frame(width: 40, height: 4).padding(.top, 3)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionEyebrow(text: pickerEyebrow(for: kind))
                        Text(pickerTitle(for: kind)).font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text(pickerSubtitle(for: kind)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.57)).lineLimit(1)
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
                                        withAnimation { picker = nil }
                                    }
                            }
                        } else if kind == .sources {
                            ForEach(servers.indices, id: \.self) { index in
                                    pickerRow(number: index + 1, title: servers[index].name, selected: index == serverIndex) {
                                        serverIndex = index
                                        controlsVisible = true
                                        withAnimation { picker = nil }
                                    }
                            }
                        } else if kind == .fit {
                            ForEach(VideoFit.allCases, id: \.self) { value in
                                pickerRow(number: VideoFit.allCases.firstIndex(of: value)! + 1, title: value.rawValue, selected: value == videoFit) {
                                    videoFit = value
                                    withAnimation { picker = nil }
                                }
                            }
                        } else {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                pickerRow(number: Int(rate * 2), title: rate == 1 ? "Bình thường · 1x" : "\(rate, specifier: "%g")x", selected: playback.playbackRate == Float(rate)) {
                                    playback.setPlaybackRate(Float(rate))
                                    withAnimation { picker = nil }
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

    private func pickerEyebrow(for kind: PickerKind) -> String {
        switch kind {
        case .episodes: return "CINEMORA · TẬP PHIM"
        case .sources: return "CINEMORA · CHẤT LƯỢNG"
        case .fit: return "CINEMORA · KHUNG HÌNH"
        case .speed: return "CINEMORA · TỐC ĐỘ"
        }
    }

    private func pickerTitle(for kind: PickerKind) -> String {
        switch kind {
        case .episodes: return "Danh sách tập"
        case .sources: return "Chọn nguồn phát"
        case .fit: return "Tỷ lệ khung hình"
        case .speed: return "Tốc độ phát"
        }
    }

    private func pickerSubtitle(for kind: PickerKind) -> String {
        switch kind {
        case .episodes: return "Đang phát: \(episode?.name ?? "")"
        case .sources: return "Đang phát: \(server?.name ?? "")"
        case .fit: return "Hiện tại: \(videoFit.rawValue)"
        case .speed: return "Hiện tại: \(playback.playbackRate, specifier: "%g")x"
        }
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
        let resume = serverIndex == initialServer && episodeIndex == initialEpisode ? Double(resumeSeconds) : 0
        playback.load(episode, startAt: resume)
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
        guard picker == nil, !volumePopoverOpen else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if (playback.isPlaying || (episode?.streamURL == nil && episode?.embedURL != nil)) && picker == nil { withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false } }
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
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

private struct NativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let fit: CinemaPlayerScreen.VideoFit

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fit.gravity
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = fit.gravity
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

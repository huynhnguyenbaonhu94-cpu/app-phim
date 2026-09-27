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

    func load(_ episode: MovieEpisode, startAt: Double? = nil) {
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
                    if let startAt, startAt > 0, startAt.isFinite {
                        let duration = item.duration.seconds
                        let safeStart = duration.isFinite && duration > 1 ? min(startAt, duration - 1) : startAt
                        self.player.seek(to: CMTime(seconds: safeStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

@MainActor
struct CinemaPlayerScreen: View {
    let movie: Movie
    let servers: [MovieServer]
    let initialServer: Int
    let initialEpisode: Int
    let resumeTime: Double?
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = PlaybackController()
    @State private var serverIndex = 0
    @State private var episodeIndex = 0
    @State private var controlsVisible = true
    @State private var picker: PickerKind?
    @State private var quickMenu: QuickMenu?
    @State private var volume = 1.0
    @State private var volumePopoverOpen = false
    @State private var controlsLocked = false
    @State private var lockIndicatorVisible = true
    @State private var settingsOpen = false
    @State private var stopTimer: StopTimer = .off
    @State private var stopAtEpisodeEnabled = false
    @State private var stopAtEpisodeID: String?
    @State private var autoAdvanceEpisodes = true
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
    private enum QuickMenu: Equatable { case videoFit, playbackRate }
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
    private var selectableStopEpisodes: [MovieEpisode] {
        var seen = Set<String>()
        return servers.flatMap(\.episodes).filter { episode in
            let key = stopEpisodeKey(episode)
            return seen.insert(key).inserted
        }
    }

    private func stopEpisodeKey(_ episode: MovieEpisode) -> String {
        let value = episode.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value.isEmpty ? episode.name : value)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    init(movie: Movie, servers: [MovieServer], initialServer: Int, initialEpisode: Int, resumeTime: Double? = nil) {
        self.movie = movie
        self.servers = servers
        self.initialServer = initialServer
        self.initialEpisode = initialEpisode
        self.resumeTime = resumeTime
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
                    NativeVideoSurface(player: playback.player, fit: videoFit).ignoresSafeArea().accessibilityLabel("Đang phát \(movie.name)")
                    Color.clear.contentShape(Rectangle()).onTapGesture { if controlsLocked { controlsLocked = false; controlsVisible = true } else { toggleControls() } }
                } else if let embed = episode?.embedURL {
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
                        if playback.isLoading { ProgressView("Đang tải nguồn phát…").tint(.white).foregroundStyle(.white).padding(18).cinemaGlass(in: Capsule(), tint: .black.opacity(0.42)) }
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
            .onChange(of: playback.currentTime) { _, _ in handlePlaybackProgress() }
            .onChange(of: stopTimer) { _, _ in scheduleStopTimer() }
            .onChange(of: stopAtEpisodeEnabled) { _, enabled in
                if enabled, stopAtEpisodeID == nil {
                    stopAtEpisodeID = episode.map { stopEpisodeKey($0) } ?? selectableStopEpisodes.first.map { stopEpisodeKey($0) }
                }
                scheduleStopTimer()
            }
            .onChange(of: stopAtEpisodeID) { _, _ in scheduleStopTimer() }
            .onAppear { loadCurrentEpisode(); scheduleHide() }
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                forceLandscape()
            }
            .onDisappear { saveLocalWatchProgress(); hideTask?.cancel(); lockHideTask?.cancel(); stopTimerTask?.cancel(); playback.shutdown(); forcePortrait() }
            .statusBarHidden(true)
        }
        .persistentSystemOverlays(.hidden)
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
            quickControl(icon: "rectangle.on.rectangle", title: "Tỷ lệ", value: videoFit.rawValue, menu: .videoFit)
            quickControl(icon: "speedometer", title: "Tốc độ", value: playbackRateLabel, menu: .playbackRate)
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
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
            if settingsOpen { settingsPanel }
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

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CÀI ĐẶT PHÁT VIDEO").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1.2).foregroundStyle(Color.cinemaAccent)
                    Text("Xem gọn hơn").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
                }
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.18)) { settingsOpen = false }; scheduleHide() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 25, height: 25)
                }.buttonStyle(.plain).accessibilityLabel("Đóng cài đặt")
            }
            settingsRow(icon: "moon.zzz.fill", title: "Tự dừng phát", detail: "Dừng sau một khoảng thời gian") {
                Picker("Tự dừng phát", selection: $stopTimer) {
                    ForEach(StopTimer.allCases) { value in Text(value.rawValue).tag(value) }
                }.labelsHidden().pickerStyle(.menu).tint(Color.cinemaAccent)
            }
            if let stopTimerRemaining {
                HStack(spacing: 7) {
                    Image(systemName: "timer").foregroundStyle(Color.cinemaAccent)
                    Text("Tự dừng sau \(formatCountdown(stopTimerRemaining))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    Spacer()
                }
                .padding(.leading, 32)
            } else if stopTimer == .endOfEpisode {
                Text("Video sẽ dừng khi hết tập hiện tại.")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55)).padding(.leading, 32)
            }
            Toggle(isOn: $stopAtEpisodeEnabled) {
                settingsLabel(icon: "stop.circle.fill", title: "Dừng ở tập đã chọn", detail: autoAdvanceEpisodes ? "Tự chuyển đến tập mục tiêu rồi dừng" : "Dừng khi xem xong tập mục tiêu")
            }.tint(Color.cinemaAccent)
            if stopAtEpisodeEnabled {
                episodeStopSelector
            }
            Toggle(isOn: $autoAdvanceEpisodes) {
                settingsLabel(icon: "forward.end.fill", title: "Tự động chuyển tập", detail: "Phát tập kế tiếp khi tập hiện tại kết thúc")
            }.tint(Color.cinemaAccent)
            Text("iOS không cho ứng dụng tự tắt nguồn thiết bị. Các lựa chọn trên sẽ tự dừng phát video an toàn.")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.48)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 315)
        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
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
                        ForEach(selectableStopEpisodes, id: \.id) { item in
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

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(formatTime(isScrubbing ? scrubValue : playback.currentTime)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).frame(width: 42, alignment: .leading)
                Slider(value: Binding(get: { isScrubbing ? scrubValue : playback.currentTime }, set: { scrubValue = $0; isScrubbing = true }), in: 0...max(1, playback.duration), onEditingChanged: { editing in if !editing { playback.seek(to: scrubValue); isScrubbing = false; scheduleHide() } })
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
        playback.load(episode, startAt: startAt)
        if startAt != nil { hasAppliedResumeTime = true }
        saveLocalWatchProgress()
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
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           #available(iOS 16.0, *) {
            let isLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
            let mask: UIInterfaceOrientationMask = isLandscape ? .landscape : .portrait
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           #available(iOS 16.0, *),
           let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
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

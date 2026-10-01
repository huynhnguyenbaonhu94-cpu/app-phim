import AVKit
import Combine
import SwiftUI
import UIKit

@MainActor
private final class TVPlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var currentURL: URL?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.isPlaying = self.player.timeControlStatus == .playing
                self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    func load(_ url: URL) {
        currentURL = url
        itemObservation = nil
        player.pause()
        isPlaying = false
        isLoading = true
        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay { self.isLoading = false }
                if item.status == .failed { self.isLoading = false }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
    }

    /// Reload the HLS playlist so AVPlayer returns to the provider's live edge.
    func refreshLiveStream() {
        guard let currentURL else { return }
        load(currentURL)
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func shutdown() {
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}

struct TVScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = TVPlaybackController()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @State private var selectedStreamID: Int?
    @State private var isMuted = false
    @State private var volume = 1.0
    @State private var isPlayerPresented = false

    private var selectedStream: TvStream? {
        guard let selectedStreamID else { return nil }
        return store.tvStreams.first { $0.id == selectedStreamID }
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
            }
        }
    }

    private func play(_ stream: TvStream) {
        guard let url = stream.streamURL else { return }
        playback.load(url)
        playback.player.volume = Float(volume)
        playback.player.isMuted = isMuted
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
        .onChange(of: volume) { _, value in playback.player.volume = Float(value) }
        .onChange(of: isMuted) { _, value in playback.player.isMuted = value }
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
                Button { playback.refreshLiveStream(); scheduleHide() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(.plain).foregroundStyle(.white).cinemaGlass(in: Circle(), tint: .black.opacity(0.36))
                .accessibilityLabel("Cập nhật thời gian phát trực tiếp")
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

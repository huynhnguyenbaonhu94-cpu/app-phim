import AVKit
import SwiftUI

struct TVScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var selectedStreamID: Int?
    @State private var player = AVPlayer()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var volume: Double = 1
    @State private var isFullscreen = false

    private var selectedStream: TvStream? {
        store.tvStreams.first { $0.id == selectedStreamID } ?? store.tvStreams.first
    }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "CINEMORA LIVE", title: "TRUYỀN HÌNH")
                    if let selectedStream {
                        VStack(alignment: .leading, spacing: 10) {
                            TVPlayerSurface(player: player, pipCoordinator: pipCoordinator, isPlaying: $isPlaying, isMuted: $isMuted, volume: $volume, isFullscreen: $isFullscreen)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            HStack(spacing: 8) {
                                Circle().fill(selectedStream.isOnline ? .green : .orange).frame(width: 7, height: 7)
                                Text(selectedStream.isOnline ? "Đang phát trực tuyến" : (selectedStream.healthMessage ?? "Đang kiểm tra nguồn"))
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.58))
                                Spacer()
                                if pipCoordinator.isSupported {
                                    Button { pipCoordinator.start() } label: { Label("PiP", systemImage: "pip") }
                                        .buttonStyle(.bordered).tint(.cinemaAccent)
                                }
                            }
                            Text(selectedStream.name).font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                            if let description = selectedStream.description, !description.isEmpty {
                                Text(description).font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
                            }
                        }
                    }
                    if store.tvLoading && store.tvStreams.isEmpty {
                        ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding(.top, 70)
                    } else if store.tvStreams.isEmpty {
                        StateMessage(icon: "tv", title: "Chưa có kênh truyền hình", detail: store.tvError ?? "Admin chưa thêm stream nào.")
                    } else {
                        SectionHeading(eyebrow: "KÊNH TRỰC TUYẾN", title: "Chọn kênh")
                        LazyVStack(spacing: 10) {
                            ForEach(store.tvStreams) { stream in
                                TVStreamRow(stream: stream, isSelected: stream.id == selectedStream?.id) {
                                    selectedStreamID = stream.id
                                    play(stream)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 36)
            }
            .refreshable { await store.startTvLiveUpdates() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.startTvLiveUpdates(); if let stream = selectedStream { play(stream) } }
        .onChange(of: selectedStreamID) { _, _ in if let stream = selectedStream { play(stream) } }
        .onChange(of: store.tvStreams) { _, streams in
            if selectedStreamID == nil { selectedStreamID = streams.first?.id }
            else if !streams.contains(where: { $0.id == selectedStreamID }) { selectedStreamID = streams.first?.id }
        }
        .onDisappear { player.pause(); store.stopTvLiveUpdates() }
        .fullScreenCover(isPresented: $isFullscreen) {
            if let selectedStream { TVFullscreenPlayer(stream: selectedStream, player: player, pipCoordinator: pipCoordinator, isPlaying: $isPlaying, isMuted: $isMuted, volume: $volume, isFullscreen: $isFullscreen) }
        }
    }

    private func play(_ stream: TvStream) {
        guard let url = stream.streamURL else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.volume = Float(volume)
        player.isMuted = isMuted
        player.play(); isPlaying = true
    }
}

private struct TVFullscreenPlayer: View {
    let stream: TvStream
    let player: AVPlayer
    let pipCoordinator: PictureInPictureCoordinator
    @Binding var isPlaying: Bool
    @Binding var isMuted: Bool
    @Binding var volume: Double
    @Binding var isFullscreen: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVPlayerSurface(player: player, pipCoordinator: pipCoordinator, isPlaying: $isPlaying, isMuted: $isMuted, volume: $volume, isFullscreen: $isFullscreen)
                .ignoresSafeArea()
            VStack { HStack { Text(stream.name).font(.headline).foregroundStyle(.white); Spacer(); Button { isFullscreen = false } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).padding(12).background(.black.opacity(0.55), in: Circle()) } }.padding(); Spacer() }
        }
        .preferredColorScheme(.dark)
    }
}

private struct TVPlayerSurface: View {
    let player: AVPlayer
    let pipCoordinator: PictureInPictureCoordinator
    @Binding var isPlaying: Bool
    @Binding var isMuted: Bool
    @Binding var volume: Double
    @Binding var isFullscreen: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            TVNativeVideoSurface(player: player, pipCoordinator: pipCoordinator)
            HStack(spacing: 14) {
                Button { if isPlaying { player.pause() } else { player.play() }; isPlaying.toggle() } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                Button { player.isMuted.toggle(); isMuted = player.isMuted } label: { Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                Slider(value: $volume, in: 0...1) { _ in player.volume = Float(volume); if volume > 0 { player.isMuted = false; isMuted = false } }
                    .tint(.white).frame(maxWidth: 130)
                Spacer()
                if pipCoordinator.isSupported { Button { pipCoordinator.start() } label: { Image(systemName: "pip") } }
                Button { isFullscreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            }
            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 15).padding(.vertical, 12)
            .background(.black.opacity(0.72))
        }
        .background(.black)
        .onChange(of: volume) { _, value in player.volume = Float(value) }
    }
}

private struct TVStreamRow: View {
    let stream: TvStream
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                AsyncImage(url: stream.posterURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image("TVPosterDefault").resizable().scaledToFill() }
                }
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
    let pipCoordinator: PictureInPictureCoordinator
    func makeUIView(context: Context) -> TVPlayerLayerView {
        let view = TVPlayerLayerView(); view.backgroundColor = .black; view.playerLayer.player = player; view.playerLayer.videoGravity = .resizeAspect
        pipCoordinator.attach(to: view.playerLayer); return view
    }
    func updateUIView(_ view: TVPlayerLayerView, context: Context) {
        view.playerLayer.player = player; pipCoordinator.attach(to: view.playerLayer)
    }
}

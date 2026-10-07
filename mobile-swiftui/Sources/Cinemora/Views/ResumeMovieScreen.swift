import SwiftUI

struct ResumeMovieScreen: View {
    let record: LocalWatchRecord
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var loadedMovie: Movie?
    @State private var showPlayer = false
    @State private var selectedServer = 0
    @State private var selectedEpisode = 0
    @State private var resumeStarted = false
    @State private var resumeError: String?

    var body: some View {
        ZStack {
            CinemaBackground()
            Group {
                if store.detailLoading {
                    ResumeLoader(title: "Đang tải lại nguồn phát…", subtitle: record.movie.name)
                } else if let error = resumeError ?? store.detailError {
                    StateMessage(icon: "wifi.exclamationmark", title: "Không thể tải nguồn phát", detail: error, actionTitle: "Thử lại") {
                        resumeError = nil
                        resumeStarted = false
                        store.loadDetail(slug: record.movie.slug)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ResumeLoader(title: "Đang mở phim…", subtitle: record.movie.name)
                }
            }
            .auroraReveal(0)
        }
        .task(id: record.movie.slug) {
            store.loadDetail(slug: record.movie.slug)
        }
        .onChange(of: store.detailMovie?.slug) { _, _ in startResumeIfReady() }
        .onAppear { startResumeIfReady() }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: { dismiss() }) {
            if let loadedMovie, !loadedMovie.availableServers.isEmpty {
                let servers = loadedMovie.availableServers
                CinemaPlayerScreen(movie: loadedMovie, servers: servers, initialServer: selectedServer, initialEpisode: selectedEpisode, resumeTime: record.watchedSeconds)
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func startResumeIfReady() {
        guard !resumeStarted, let movie = store.detailMovie, movie.slug == record.movie.slug else { return }
        let servers = movie.availableServers
        guard !servers.isEmpty else {
            resumeError = "Phim chưa có nguồn phát khả dụng. Hãy mở lại trang chi tiết để thử nguồn khác."
            return
        }
        var resolvedServer = record.serverName.flatMap { savedName in
            servers.firstIndex(where: { $0.name == savedName })
        } ?? 0
        if servers[resolvedServer].episodes.isEmpty,
           let playableServer = servers.firstIndex(where: { !$0.episodes.isEmpty }) {
            resolvedServer = playableServer
        }
        if let savedSlug = record.episodeSlug,
           !servers[resolvedServer].episodes.contains(where: { $0.slug == savedSlug }),
           let serverWithEpisode = servers.firstIndex(where: { $0.episodes.contains(where: { $0.slug == savedSlug }) }) {
            resolvedServer = serverWithEpisode
        } else if let savedName = record.episodeName,
                  !servers[resolvedServer].episodes.contains(where: { $0.name == savedName }),
                  let serverWithEpisode = servers.firstIndex(where: { $0.episodes.contains(where: { $0.name == savedName }) }) {
            resolvedServer = serverWithEpisode
        }
        let hasSavedEpisode: (MovieEpisode) -> Bool = { item in
            if let savedSlug = record.episodeSlug, item.slug == savedSlug { return true }
            if let savedName = record.episodeName, item.name == savedName { return true }
            return false
        }
        if !servers[resolvedServer].episodes.contains(where: hasSavedEpisode),
           let serverWithSavedEpisode = servers.firstIndex(where: { $0.episodes.contains(where: hasSavedEpisode) }) {
            resolvedServer = serverWithSavedEpisode
        }
        selectedServer = resolvedServer
        let episodes = servers[resolvedServer].episodes
        if let savedSlug = record.episodeSlug, let index = episodes.firstIndex(where: { $0.slug == savedSlug }) {
            selectedEpisode = index
        } else if let savedName = record.episodeName, let index = episodes.firstIndex(where: { $0.name == savedName }) {
            selectedEpisode = index
        }
        guard episodes.indices.contains(selectedEpisode),
              episodes[selectedEpisode].streamURL != nil || episodes[selectedEpisode].embedURL != nil else {
            resumeError = "Nguồn phát của tập này không còn khả dụng. Hãy mở trang chi tiết và chọn nguồn khác."
            return
        }
        loadedMovie = movie
        resumeStarted = true
        showPlayer = true
    }
}

/// Animated "resuming" indicator: a rotating aurora ring around a film glyph.
private struct ResumeLoader: View {
    let title: String
    let subtitle: String
    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    .frame(width: 92, height: 92)
                Circle()
                    .trim(from: 0, to: 0.32)
                    .stroke(LinearGradient.auroraPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Circle()
                    .fill(Color.auroraViolet.opacity(0.22))
                    .frame(width: 62, height: 62)
                    .blur(radius: 12)
                    .scaleEffect(breathe ? 1.14 : 0.9)
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(LinearGradient.auroraPrimary)
                    .offset(x: 1)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.auroraLabel(14, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.auroraBody(11))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

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
            Color.cinemaInk.ignoresSafeArea()
            if store.detailLoading {
                ProgressView("Đang tải lại nguồn phát…")
                    .tint(.cinemaAccent)
                    .foregroundStyle(.white)
            } else if let error = resumeError ?? store.detailError {
                StateMessage(icon: "wifi.exclamationmark", title: "Không thể tải nguồn phát", detail: error, actionTitle: "Thử lại") {
                    resumeError = nil
                    resumeStarted = false
                    store.loadDetail(slug: record.movie.slug)
                }
            } else {
                ProgressView("Đang mở phim…")
                    .tint(.cinemaAccent)
                    .foregroundStyle(.white)
            }
        }
        .task(id: record.movie.slug) {
            store.loadDetail(slug: record.movie.slug)
        }
        .onChange(of: store.detailMovie?.slug) { _, _ in startResumeIfReady() }
        .onAppear { startResumeIfReady() }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: { dismiss() }) {
            if let loadedMovie, let servers = loadedMovie.servers, !servers.isEmpty {
                CinemaPlayerScreen(movie: loadedMovie, servers: servers, initialServer: selectedServer, initialEpisode: selectedEpisode, resumeTime: record.watchedSeconds)
                    .environmentObject(store)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func startResumeIfReady() {
        guard !resumeStarted, let movie = store.detailMovie, movie.slug == record.movie.slug else { return }
        guard let servers = movie.servers, !servers.isEmpty else {
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

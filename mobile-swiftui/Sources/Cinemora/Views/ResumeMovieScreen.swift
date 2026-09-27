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

    var body: some View {
        ZStack {
            Color.cinemaInk.ignoresSafeArea()
            if store.detailLoading {
                ProgressView("Đang tải lại nguồn phát…")
                    .tint(.cinemaAccent)
                    .foregroundStyle(.white)
            } else if let error = store.detailError {
                StateMessage(icon: "wifi.exclamationmark", title: "Không thể tải nguồn phát", detail: error, actionTitle: "Thử lại") {
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
        .onChange(of: store.detailMovie?.id) { _, _ in startResumeIfReady() }
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
        guard let servers = movie.servers, !servers.isEmpty else { return }
        loadedMovie = movie
        if let savedServer = record.serverName, let index = servers.firstIndex(where: { $0.name == savedServer }) {
            selectedServer = index
        }
        let episodes = servers[selectedServer].episodes
        if let savedSlug = record.episodeSlug, let index = episodes.firstIndex(where: { $0.slug == savedSlug }) {
            selectedEpisode = index
        } else if let savedName = record.episodeName, let index = episodes.firstIndex(where: { $0.name == savedName }) {
            selectedEpisode = index
        }
        resumeStarted = true
        showPlayer = true
    }
}

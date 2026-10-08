import SwiftUI

struct MovieDetailScreen: View {
    let slug: String
    private let autoPlayOnLoad: Bool
    private let onExitRelated: (() -> Void)?
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedServer = 0
    @State private var selectedEpisode = 0
    @State private var showPlayer = false
    @State private var relatedMovieRoute: Movie?
    @State private var didAutoStartPlayback = false
    @State private var showLoginPrompt = false
    @State private var showLogin = false

    init(slug: String, autoPlayOnLoad: Bool = false, onExitRelated: (() -> Void)? = nil) {
        self.slug = slug
        self.autoPlayOnLoad = autoPlayOnLoad
        self.onExitRelated = onExitRelated
    }

    private var movie: Movie? { store.detailMovie }
    private var servers: [MovieServer] { movie?.availableServers ?? [] }
    private var episodes: [MovieEpisode] { servers.indices.contains(selectedServer) ? servers[selectedServer].episodes : [] }
    private var episode: MovieEpisode? { episodes.indices.contains(selectedEpisode) ? episodes[selectedEpisode] : nil }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 40, 280), 720)

            ZStack {
                CinemaBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let movie {
                            detailContent(movie, width: contentWidth)
                        } else if store.detailLoading {
                            loadingState
                                .frame(width: contentWidth)
                                .padding(.top, 150)
                        } else {
                            StateMessage(icon: "wifi.exclamationmark", title: "Không tải được phim", detail: store.detailError, actionTitle: "Thử lại") { store.loadDetail(slug: slug) }
                                .frame(width: contentWidth)
                                .padding(.top, 80)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.top, 58)
                    .padding(.bottom, 112)
                }
                .frame(maxWidth: .infinity)
                .scrollIndicators(.hidden)
            }
            .overlay(alignment: .topLeading) {
                AuroraBackButton(title: "Trở lại") { dismissDetail() }
                    .padding(.leading, 20)
                    .padding(.top, 8)
            }
            .modifier(EdgeBackDrag(onBack: { dismissDetail() }))
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Cần đăng nhập", isPresented: $showLoginPrompt) {
            Button("Đăng nhập") { showLogin = true }
            Button("Để sau", role: .cancel) { }
        } message: {
            Text("Bạn cần đăng nhập để lưu phim vào danh sách yêu thích. Danh sách yêu thích được đồng bộ theo tài khoản của bạn.")
        }
        .sheet(isPresented: $showLogin) {
            AccountSettingsScreen()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .task(id: slug) { store.loadDetail(slug: slug) }
        .onChange(of: store.detailMovie?.id) { _, _ in selectedServer = 0; selectedEpisode = 0 }
        .onChange(of: store.detailMovie?.slug) { _, loadedSlug in
            guard autoPlayOnLoad,
                  !didAutoStartPlayback,
                  loadedSlug == slug,
                  let loadedMovie = store.detailMovie else { return }
            didAutoStartPlayback = true
            guard let playableServerIndex = loadedMovie.availableServers.firstIndex(where: { !$0.episodes.isEmpty }) else { return }
            selectedServer = playableServerIndex
            selectedEpisode = 0
            // Both lookups were unchecked: a stale server index, or a server
            // whose episode list is empty, crashed right here.
            guard loadedMovie.availableServers.indices.contains(playableServerIndex),
                  let playableEpisode = loadedMovie.availableServers[playableServerIndex].episodes.first
            else { return }
            store.recordLocalHistory(movie: loadedMovie, episode: playableEpisode, serverName: loadedMovie.availableServers[playableServerIndex].name)
            startPlayback()
        }
        .onChange(of: selectedServer) { _, _ in selectedEpisode = 0 }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: {
            if relatedMovieRoute != nil {
                relatedMovieRoute = nil
                // Khi đóng chi tiết B, bỏ luôn player/phim A bên dưới để
                // người dùng trở về màn hình app, không quay lại A.
                dismissDetail()
            }
        }) {
            Group {
                if let relatedMovieRoute {
                    MovieDetailScreen(
                        slug: relatedMovieRoute.slug,
                        autoPlayOnLoad: true,
                        onExitRelated: { showPlayer = false }
                    )
                        .environment(store)
                        .preferredColorScheme(.dark)
                } else if let movie, episode != nil {
                    CinemaPlayerScreen(
                        movie: movie,
                        servers: servers,
                        initialServer: selectedServer,
                        initialEpisode: selectedEpisode,
                        onOpenRelated: { related in relatedMovieRoute = related }
                    )
                        .preferredColorScheme(.dark)
                }
            }
            .id(relatedMovieRoute?.id ?? "cinemora-player-\(slug)")
        }
    }

    /// Turns the device to landscape first and only then opens the player, so
    /// the player never shows up in portrait and rotates a beat later.
    private func startPlayback() {
        guard !showPlayer else { return }
        OrientationSupport.rotateThenPresent { showPlayer = true }
    }

    private func dismissDetail() {
        if let onExitRelated {
            onExitRelated()
        } else {
            dismiss()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            SkeletonBlock(cornerRadius: 30)
                .frame(height: 430)
            SkeletonPosterGrid(count: 4)
        }
    }

    // MARK: - Content

    @ViewBuilder private func detailContent(_ movie: Movie, width: CGFloat) -> some View {
        heroSection(movie, width: width)
            .auroraReveal(0)

        if let description = movie.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(eyebrow: "CÂU CHUYỆN", title: "Nội dung phim")
                Text(description)
                    .font(.auroraBody(13))
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width, alignment: .leading)
            .auroraReveal(1)
        }

        HStack(spacing: 8) {
            if let rating = movie.rating, rating > 0 {
                metricPill(icon: "star.fill", title: "Đánh giá", value: String(format: "%.1f/10", rating), tint: .auroraAmber)
            }
            if let views = movie.views {
                metricPill(icon: "eye.fill", title: "Lượt xem", value: formattedViews(views), tint: .auroraSky)
            }
            if let status = movie.status, !status.isEmpty {
                metricPill(icon: "circle.fill", title: "Cập nhật", value: status, tint: .auroraMint)
            }
        }
        .frame(width: width, alignment: .leading)
        .auroraReveal(2)

        if let profiles = movie.actorProfiles, !profiles.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeading(eyebrow: "DIỄN VIÊN", title: "Dàn diễn viên")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 13) {
                        ForEach(profiles) { profile in actorCard(profile) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
            .frame(width: width, alignment: .leading)
            .auroraReveal(3)
        }

        if !servers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(eyebrow: "SẴN SÀNG PHÁT", title: "Tập & nguồn")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(servers.indices, id: \.self) { index in
                            let server = servers[index]
                            serverChip(server, selected: selectedServer == index) {
                                withAnimation(Motion.gentle) { selectedServer = index }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(episodes.indices, id: \.self) { index in
                        let item = episodes[index]
                        Button {
                            selectedEpisode = index
                            store.recordLocalHistory(movie: movie, episode: item, serverName: servers.indices.contains(selectedServer) ? servers[selectedServer].name : nil)
                            startPlayback()
                        } label: {
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(selectedEpisode == index ? Color.auroraVoid : Color.auroraViolet)
                                Text(item.name)
                                    .font(.auroraLabel(11, weight: .bold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if selectedEpisode == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.auroraVoid)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .foregroundStyle(selectedEpisode == index ? Color.auroraVoid : .white.opacity(0.86))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .background {
                                if selectedEpisode == index {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous).fill(LinearGradient.auroraPrimary)
                                } else {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.white.opacity(0.075))
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .strokeBorder(Color.white.opacity(selectedEpisode == index ? 0.3 : 0.09), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.auroraPress(scale: 0.96))
                        .animation(Motion.gentle, value: selectedEpisode)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .auroraReveal(4)
        }

        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(eyebrow: "THÔNG TIN", title: "Về bộ phim")
            VStack(spacing: 0) {
                metadataRow("Thể loại", movie.categories?.map(\.name).joined(separator: ", "))
                metadataRow("Quốc gia", movie.countries?.map(\.name).joined(separator: ", "))
                metadataRow("Đạo diễn", movie.directors?.joined(separator: ", "))
                if movie.actorProfiles?.isEmpty != false { metadataRow("Diễn viên", movie.actors?.joined(separator: ", ")) }
                metadataRow("Đánh giá", movie.rating.map { String(format: "%.1f/10", $0) })
                metadataRow("Lượt xem", movie.views.map { formattedViews($0) })
                metadataRow("Cập nhật", movie.updatedAt.map { formattedDate($0) })
            }
            .padding(16)
            .auroraCard(cornerRadius: 24, tint: .auroraViolet, fill: 0.6)
        }
        .frame(width: width, alignment: .leading)
        .auroraReveal(5)

        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(eyebrow: "THÔNG TIN BỔ SUNG", title: "Thông tin khác")
            VStack(spacing: 0) {
                metadataRow("Tên khác", movie.alternativeNames?.joined(separator: ", "))
                metadataRow("Tập hiện tại", movie.episodeCurrent)
                metadataRow("Ngày tạo", movie.createdAt.map { formattedDate($0) })
                metadataRow("TMDB", movie.tmdbId)
                metadataRow("IMDB", movie.imdbId)
            }
            .padding(16)
            .auroraCard(cornerRadius: 24, tint: .auroraSky, fill: 0.6)
        }
        .frame(width: width, alignment: .leading)
        .auroraReveal(6)
    }

    private func heroSection(_ movie: Movie, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterArt(url: movie.backdropURL).frame(width: width, height: 440)
            LinearGradient(
                colors: [Color.clear, Color.auroraInk.opacity(0.3), Color.auroraInk],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 10) {
                if let quality = movie.quality {
                    Text(quality.uppercased())
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Color.auroraVoid)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient.auroraPrimary))
                }
                Text(movie.name)
                    .font(.auroraDisplay(30))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
                if let origin = movie.originName, !origin.isEmpty {
                    Text(origin)
                        .font(.auroraBody(13))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let year = movie.year { metaChip(String(year)) }
                    if let time = movie.time, !time.isEmpty { metaChip(time) }
                    if let lang = movie.lang, !lang.isEmpty { metaChip(lang) }
                    if let rating = movie.rating, rating > 0 { metaChip(String(format: "★ %.1f", rating)) }
                }
                Button {
                    store.recordLocalHistory(movie: movie, episode: episode, serverName: servers.indices.contains(selectedServer) ? servers[selectedServer].name : nil)
                    startPlayback()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text(episode == nil ? "Chưa có nguồn phát" : "Xem phim")
                    }
                    .font(.auroraLabel(13, weight: .black))
                    .foregroundStyle(Color.auroraVoid)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient.auroraPrimary))
                    .auroraHalo(.auroraViolet, radius: 22, opacity: episode == nil ? 0 : 0.5)
                }
                .buttonStyle(.auroraPress(scale: 0.96))
                .disabled(episode == nil)
                .opacity(episode == nil ? 0.5 : 1)
                .padding(.top, 6)
            }
            .padding(22)
        }
        .frame(width: width, height: 440, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(LinearGradient.auroraVeil, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .shadow(color: Color.auroraViolet.opacity(0.22), radius: 28, y: 12)
        .overlay(alignment: .topTrailing) {
            Button {
                // Favourites live on the account, so ask for a sign-in instead
                // of silently doing nothing.
                guard store.accountUser != nil else {
                    showLoginPrompt = true
                    return
                }
                withAnimation(Motion.tap) { store.toggleFavorite(movie) }
            } label: {
                Image(systemName: store.isFavorite(movie) ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(store.isFavorite(movie) ? Color.auroraPink : .white)
                    .frame(width: 46, height: 46)
                    .contentTransition(.symbolEffect(.replace))
                    .background {
                        Circle().fill(Color.black.opacity(0.42))
                    }
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .padding(16)
            .accessibilityLabel(store.isFavorite(movie) ? "Bỏ yêu thích" : "Thêm vào yêu thích")
        }
    }

    private func serverChip(_ server: MovieServer, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: server.isAi ? "sparkles" : "play.rectangle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(server.name)
                    .font(.auroraLabel(10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.auroraVoid : .white.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                if selected {
                    Capsule().fill(LinearGradient.auroraPrimary)
                } else {
                    Capsule().fill(Color.white.opacity(0.07))
                }
            }
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(selected ? 0.3 : 0.09), lineWidth: 0.8)
            }
        }
        .buttonStyle(.auroraPress(scale: 0.94))
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
    }

    private func metricPill(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)
            Text(value)
                .font(.auroraLabel(11, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.7)
        }
    }

    private func actorCard(_ profile: MovieActorProfile) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: profile.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.auroraViolet.opacity(0.75))
                    }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 76, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 12, y: 7)

            Text(profile.name)
                .font(.auroraLabel(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 86)
        }
    }

    private func formattedViews(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formattedDate(_ value: String) -> String {
        let input = ISO8601DateFormatter()
        input.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = input.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return value }
        let output = DateFormatter()
        output.locale = Locale(identifier: "vi_VN")
        output.dateFormat = "dd/MM/yyyy"
        return output.string(from: date)
    }

    private func metadataRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.auroraBody(10, weight: .semibold))
                .foregroundStyle(Color.auroraTextTertiary)
                .frame(width: 76, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "Đang cập nhật")
                .font(.auroraBody(10))
                .foregroundStyle(.white.opacity(value?.isEmpty == false ? 0.84 : 0.36))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
        }
    }
}

import SwiftUI

struct MovieDetailScreen: View {
    let slug: String
    private let autoPlayOnLoad: Bool
    private let onExitRelated: (() -> Void)?
    private let offlineGuardEnabled: Bool
    @Environment(CinemaStore.self) private var store
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @State private var selectedServer = 0
    @State private var selectedEpisode = 0
    @State private var showPlayer = false
    @State private var showDownloadSheet = false
    @State private var relatedMovieRoute: Movie?
    @State private var didAutoStartPlayback = false
    @State private var showLoginPrompt = false
    @State private var showLogin = false

    init(slug: String, autoPlayOnLoad: Bool = false, onExitRelated: (() -> Void)? = nil, offlineGuardEnabled: Bool = false) {
        self.slug = slug
        self.autoPlayOnLoad = autoPlayOnLoad
        self.onExitRelated = onExitRelated
        self.offlineGuardEnabled = offlineGuardEnabled
    }

    private var movie: Movie? { store.detail(for: slug) }
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
                        if connectivity.isConnected, store.isDetailLoading(slug), movie != nil {
                            detailRefreshIndicator
                                .frame(width: contentWidth, alignment: .leading)
                        }
                        if !connectivity.isConnected, movie != nil {
                            offlineNotice(hasCachedMovie: true) {
                                store.loadDetail(slug: slug)
                            }
                            .frame(width: contentWidth)
                        }
                        if let movie {
                            detailContent(movie, width: contentWidth)
                            // Bình luận của phim này, ngay dưới phần nội dung.
                            CommentsSection(movie: movie)
                                .padding(.top, 4)
                        } else if !connectivity.isConnected {
                            offlineState {
                                store.loadDetail(slug: slug)
                            }
                            .frame(width: contentWidth)
                            .padding(.top, 100)
                        } else if store.isDetailLoading(slug) {
                            loadingState(width: contentWidth)
                                .frame(width: contentWidth)
                                .padding(.top, 70)
                        } else {
                            StateMessage(icon: "wifi.exclamationmark", title: "Không tải được phim", detail: store.detailError(for: slug), actionTitle: "Thử lại") { store.loadDetail(slug: slug) }
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
            AccountSettingsScreen(offlineGuardEnabled: true)
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .task(id: slug) { store.loadDetail(slug: slug) }
        .onChange(of: connectivity.isConnected) { wasConnected, isConnected in
            guard !wasConnected, isConnected, movie == nil else { return }
            store.loadDetail(slug: slug)
        }
        .onChange(of: store.detail(for: slug)?.id) { _, _ in selectedServer = 0; selectedEpisode = 0 }
        .onChange(of: store.detail(for: slug)?.slug) { _, loadedSlug in
            guard autoPlayOnLoad,
                  !didAutoStartPlayback,
                  loadedSlug == slug,
                  let loadedMovie = store.detail(for: slug) else { return }
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
        .sheet(isPresented: $showDownloadSheet) {
            if let movie {
                DownloadSheet(movie: movie, servers: servers, initialServer: selectedServer)
            }
        }
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
                        onExitRelated: { showPlayer = false },
                        offlineGuardEnabled: true
                    )
                        .environment(store)
                        .preferredColorScheme(.dark)
                } else if let movie, episode != nil {
                    CinemaPlayerScreen(
                        movie: movie,
                        servers: servers,
                        initialServer: selectedServer,
                        initialEpisode: selectedEpisode,
                        subtitleCustomizationEnabled: true,
                        onOpenRelated: { related in relatedMovieRoute = related }
                    )
                        .preferredColorScheme(.dark)
                }
            }
            .id(relatedMovieRoute?.id ?? "cinemora-player-\(slug)")
        }
        .overlay {
            if offlineGuardEnabled && !connectivity.isConnected {
                NetworkUnavailableOverlay()
                    .transition(.opacity)
                    .zIndex(100)
            }
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

    private var detailRefreshIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.auroraAccent)
            Text("Đang cập nhật thông tin phim")
                .font(.auroraLabel(10, weight: .semibold))
                .foregroundStyle(Color.auroraTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.auroraRaised.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.auroraHairline, lineWidth: 0.8))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel("Đang cập nhật thông tin phim")
    }

    private func loadingState(width: CGFloat) -> some View {
        let heroHeight = min(max(width * 1.08, 300), 390)
        return VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.auroraRaised, Color.auroraInk, Color.auroraViolet.opacity(0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Circle()
                    .fill(RadialGradient(colors: [Color.auroraSky.opacity(0.26), .clear], center: .center, startRadius: 4, endRadius: width * 0.48))
                    .frame(width: width * 0.92, height: width * 0.92)
                    .offset(x: width * 0.34, y: -heroHeight * 0.25)
                AuroraShimmerOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.auroraAccent)
                        Text("CINEMORA")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        Text("ĐANG TẢI")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Color.auroraAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.auroraAccent.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 14)

                    HStack(spacing: 13) {
                        DetailLoadingMark()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("ĐANG CHUẨN BỊ PHIM")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .tracking(1.1)
                                .foregroundStyle(Color.auroraSky.opacity(0.95))
                            Text("Đang tải thông tin")
                                .font(.auroraLabel(12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Một chút nữa thôi…")
                                .font(.auroraBody(10))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    Spacer(minLength: 14)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 66, height: 13)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: width * 0.68, height: 25)
                        .padding(.top, 9)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: width * 0.46, height: 11)
                        .padding(.top, 7)
                    HStack(spacing: 8) {
                        loadingPill(width: 52)
                        loadingPill(width: 76)
                        loadingPill(width: 66)
                    }
                    .padding(.top, 12)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.auroraAccent.opacity(0.72))
                        .frame(width: 124, height: 42)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(Color.auroraVoid.opacity(0.7))
                        }
                        .padding(.top, 15)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: width, height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(LinearGradient.auroraVeil, lineWidth: 1)
            }

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: 16).frame(height: 52)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                SkeletonBlock(cornerRadius: 6).frame(width: 115, height: 13)
                SkeletonBlock(cornerRadius: 6).frame(height: 11)
                SkeletonBlock(cornerRadius: 6).frame(width: width * 0.83, height: 11)
                SkeletonBlock(cornerRadius: 6).frame(width: width * 0.59, height: 11)
            }
            .padding(14)
            .auroraCard(cornerRadius: 22, tint: .auroraViolet, fill: 0.5)

            HStack {
                SkeletonBlock(cornerRadius: 6).frame(width: 145, height: 17)
                Spacer()
                SkeletonBlock(cornerRadius: 12).frame(width: 86, height: 30)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: 16).frame(height: 52)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Đang tải chi tiết phim")
    }

    private func offlineNotice(hasCachedMovie: Bool, retry: @escaping () -> Void) -> some View {
        OfflineDetailConnectionCard(compact: true, hasCachedMovie: hasCachedMovie, retry: retry)
    }

    private func offlineState(retry: @escaping () -> Void) -> some View {
        OfflineDetailConnectionCard(compact: false, hasCachedMovie: false, retry: retry)
    }

    private func loadingPill(width: CGFloat) -> some View {
        Capsule().fill(Color.white.opacity(0.10)).frame(width: width, height: 22)
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
                HStack(alignment: .firstTextBaseline) {
                    SectionHeading(eyebrow: "SẴN SÀNG PHÁT", title: "Tập & nguồn")
                    Spacer(minLength: 0)
                    Button {
                        showDownloadSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill").font(.system(size: 12, weight: .bold))
                            Text("Tải xuống").font(.auroraLabel(11, weight: .bold))
                        }
                        .foregroundStyle(Color.auroraViolet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.auroraViolet.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tải phim về máy")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Enumerated snapshot with element identity, never
                        // `servers[index]`. A reload replaces `movie`, so the
                        // server list can shrink while this row is still on
                        // screen — indexing it then traps "Index out of range"
                        // and takes the app down.
                        ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                            serverChip(server, selected: selectedServer == index) {
                                withAnimation(Motion.gentle) { selectedServer = index }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, item in
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

    /// Đổi mọi dạng ngày của máy chủ sang dd/MM/yyyy.
    ///
    /// Phim lấy từ API trả mốc ISO 8601 đầy đủ, còn phim thêm thủ công trả chuỗi
    /// admin nhập (yyyy-MM-dd hoặc kèm giờ). Trước đây chuỗi dạng ngày bị bỏ qua
    /// nên hiện nguyên "2026-10-14"; nay phân tích cả hai kiểu.
    private func formattedDate(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return raw }

        let output = DateFormatter()
        output.locale = Locale(identifier: "vi_VN")
        output.dateFormat = "dd/MM/yyyy"

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = internet.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return output.string(from: date)
        }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd", "yyyy/MM/dd"] {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone.current
            parser.dateFormat = format
            if let date = parser.date(from: raw) { return output.string(from: date) }
        }
        return raw
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

private struct DetailLoadingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0.04, to: 0.34)
                .stroke(
                    AngularGradient(colors: [.auroraSky, .auroraViolet, .auroraAccent], center: .center),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                )
                .rotationEffect(.degrees(isRotating ? 360 : 0))
            Circle()
                .fill(Color.white.opacity(0.055))
                .padding(8)
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color.auroraAccent)
                .offset(x: 1)
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
        .onAppear(perform: startRotation)
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce { isRotating = false } else { startRotation() }
        }
    }

    private func startRotation() {
        guard !reduceMotion, !isRotating else { return }
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            isRotating = true
        }
    }
}

private struct OfflineDetailConnectionCard: View {
    let compact: Bool
    let hasCachedMovie: Bool
    let retry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var title: String {
        hasCachedMovie ? "Đang ngoại tuyến" : "Không có kết nối Internet"
    }

    private var message: String {
        hasCachedMovie
            ? "Thông tin phim đã tải trước đó vẫn hiển thị. Cần mạng để tải nội dung mới hoặc phát video."
            : "Hãy kiểm tra Wi‑Fi hoặc dữ liệu di động rồi thử tải lại trang phim."
    }

    var body: some View {
        Group {
            if compact {
                compactContent
            } else {
                offlineContent
            }
        }
        .padding(compact ? 13 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                .fill(Color.auroraRaised.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                        .fill(LinearGradient(colors: [Color.auroraAmber.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                .strokeBorder(Color.auroraAmber.opacity(0.28), lineWidth: 0.9)
        }
        .shadow(color: Color.black.opacity(compact ? 0.08 : 0.22), radius: 18, y: 8)
        .onAppear(perform: startPulse)
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce { pulse = false } else { startPulse() }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            wifiIcon(size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.auroraLabel(11, weight: .black))
                    .foregroundStyle(.white)
                Text(hasCachedMovie ? "Đang hiển thị thông tin đã tải sẵn." : "Kiểm tra Wi‑Fi hoặc dữ liệu di động.")
                    .font(.auroraBody(10))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(action: retry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.auroraVoid)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LinearGradient.auroraPrimary))
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .accessibilityLabel("Thử tải lại chi tiết phim")
        }
    }

    private var offlineContent: some View {
        VStack(spacing: 15) {
            wifiIcon(size: 68)
                .padding(.top, 4)
            VStack(spacing: 7) {
                Text(title)
                    .font(.auroraDisplay(20))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.auroraBody(12))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 310)
            }
            Button(action: retry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Thử lại")
                }
                .font(.auroraLabel(12, weight: .black))
                .foregroundStyle(Color.auroraVoid)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(LinearGradient.auroraPrimary))
            }
            .buttonStyle(.auroraPress(scale: 0.96))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func wifiIcon(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.auroraAmber.opacity(pulse ? 0.04 : 0.13))
                .frame(width: size, height: size)
                .scaleEffect(pulse && !reduceMotion ? 1.16 : 0.92)
            Circle()
                .fill(Color.auroraAmber.opacity(0.10))
                .frame(width: size * 0.78, height: size * 0.78)
            Image(systemName: "wifi.slash")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(Color.auroraAmber)
                .symbolEffect(.pulse, value: pulse && !reduceMotion)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func startPulse() {
        guard !reduceMotion, !pulse else { return }
        withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

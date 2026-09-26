import SwiftUI

struct MovieDetailScreen: View {
    let slug: String
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedServer = 0
    @State private var selectedEpisode = 0
    @State private var showPlayer = false
    @State private var favorite = false
    @State private var favoriteBusy = false
    private let api = CinemaAPI.shared

    private var movie: Movie? { store.detailMovie }
    private var servers: [MovieServer] { movie?.servers ?? [] }
    private var episodes: [MovieEpisode] { servers.indices.contains(selectedServer) ? servers[selectedServer].episodes : [] }
    private var episode: MovieEpisode? { episodes.indices.contains(selectedEpisode) ? episodes[selectedEpisode] : nil }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 40, 280), 720)

            ZStack {
                CinemaBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let movie {
                            detailContent(movie, width: contentWidth)
                        } else if store.detailLoading {
                            ProgressView("Đang tải chi tiết phim…")
                                .tint(.cinemaAccent)
                                .foregroundStyle(.white.opacity(0.65))
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
                Button { dismiss() } label: {
                    Label("Trở lại", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.5), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.top, 8)
                .accessibilityLabel("Trở lại danh sách phim")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: slug) {
            store.loadDetail(slug: slug)
            favorite = (try? await api.isFavorite(slug: slug)) ?? false
        }
        .onChange(of: store.detailMovie?.id) { _, _ in selectedServer = 0; selectedEpisode = 0 }
        .onChange(of: selectedServer) { _, _ in selectedEpisode = 0 }
        .fullScreenCover(isPresented: $showPlayer) {
            if let movie, episode != nil {
                CinemaPlayerScreen(movie: movie, servers: servers, initialServer: selectedServer, initialEpisode: selectedEpisode)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func toggleFavorite(_ movie: Movie) async {
        favoriteBusy = true
        do {
            if favorite { try await api.removeFavorite(slug: movie.slug) }
            else { try await api.addFavorite(movie: movie) }
            favorite.toggle()
        } catch { }
        favoriteBusy = false
    }

    @ViewBuilder private func detailContent(_ movie: Movie, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterArt(url: movie.backdropURL).frame(width: width, height: 430)
            LinearGradient(colors: [.clear, Color.cinemaInk.opacity(0.25), Color.cinemaInk], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                if let quality = movie.quality { Text(quality.uppercased()).font(.system(size: 9, weight: .black)).tracking(1).foregroundStyle(Color.cinemaAccent).padding(.horizontal, 9).padding(.vertical, 6).background(.black.opacity(0.42), in: Capsule()) }
                Text(movie.name).font(.system(size: 30, weight: .black, design: .rounded)).tracking(-0.7).foregroundStyle(.white).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if let origin = movie.originName, !origin.isEmpty { Text(origin).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(2) }
                HStack(spacing: 8) {
                    if let year = movie.year { metaChip(String(year)) }
                    if let time = movie.time, !time.isEmpty { metaChip(time) }
                    if let lang = movie.lang, !lang.isEmpty { metaChip(lang) }
                    if let rating = movie.rating, rating > 0 { metaChip(String(format: "★ %.1f", rating)) }
                }
                HStack(spacing: 9) {
                    Button { showPlayer = true } label: {
                        Label(episode == nil ? "Chưa có nguồn phát" : "Xem phim", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Color.cinemaInk)
                            .padding(.horizontal, 20).padding(.vertical, 13).background(Color.cinemaAccent, in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(episode == nil).opacity(episode == nil ? 0.5 : 1)
                    Button { Task { await toggleFavorite(movie) } } label: {
                        Image(systemName: favorite ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(favorite ? Color.cinemaInk : .white)
                            .frame(width: 46, height: 46).background(favorite ? Color.cinemaAccent : .white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(favoriteBusy).accessibilityLabel(favorite ? "Bỏ yêu thích" : "Thêm vào yêu thích")
                }
                .padding(.top, 5)
            }
            .padding(22)
        }
        .frame(width: width, height: 430, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.16), lineWidth: 0.8))

        if let description = movie.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeading(eyebrow: "CÂU CHUYỆN", title: "Nội dung phim")
                Text(description)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width, alignment: .leading)
        }

        HStack(spacing: 8) {
            if let rating = movie.rating, rating > 0 { metricPill(icon: "star.fill", title: "Đánh giá", value: String(format: "%.1f/10", rating)) }
            if let views = movie.views { metricPill(icon: "eye.fill", title: "Lượt xem", value: formattedViews(views)) }
            if let status = movie.status, !status.isEmpty { metricPill(icon: "circle.fill", title: "Cập nhật", value: status) }
        }
        .frame(width: width, alignment: .leading)

        if let profiles = movie.actorProfiles, !profiles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(eyebrow: "DIỄN VIÊN", title: "Dàn diễn viên")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(profiles) { profile in actorCard(profile) }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }

        if !servers.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeading(eyebrow: "SẴN SÀNG PHÁT", title: "Tập & nguồn")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(servers.indices, id: \.self) { index in
                            let server = servers[index]
                            Button { selectedServer = index } label: {
                                Label(server.name, systemImage: server.isAi ? "sparkles" : "play.rectangle")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(selectedServer == index ? Color.cinemaInk : .white.opacity(0.76))
                                    .padding(.horizontal, 13).padding(.vertical, 10)
                                    .background(selectedServer == index ? Color.cinemaAccent : Color.white.opacity(0.07), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(episodes.indices, id: \.self) { index in
                        let item = episodes[index]
                        Button { selectedEpisode = index; showPlayer = true } label: {
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(selectedEpisode == index ? Color.cinemaInk : Color.cinemaAccent)
                                Text(item.name).font(.system(size: 11, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if selectedEpisode == index { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color.cinemaInk) }
                            }
                            .foregroundStyle(selectedEpisode == index ? Color.cinemaInk : .white.opacity(0.84))
                            .padding(.horizontal, 12).frame(minHeight: 50)
                            .background(selectedEpisode == index ? Color.cinemaAccent : Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 12) {
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
            .padding(15).cinemaGlass(in: RoundedRectangle(cornerRadius: 22), tint: .white.opacity(0.045))
        }
        .frame(width: width, alignment: .leading)

        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(eyebrow: "THÔNG TIN BỔ SUNG", title: "Thông tin khác")
            VStack(spacing: 0) {
                metadataRow("Tên khác", movie.alternativeNames?.joined(separator: ", "))
                metadataRow("Tập hiện tại", movie.episodeCurrent)
                metadataRow("Ngày tạo", movie.createdAt.map { formattedDate($0) })
                metadataRow("TMDB", movie.tmdbId)
                metadataRow("IMDB", movie.imdbId)
            }
            .padding(15).cinemaGlass(in: RoundedRectangle(cornerRadius: 22), tint: .white.opacity(0.045))
        }
        .frame(width: width, alignment: .leading)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.86)).padding(.horizontal, 9).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule())
    }

    private func metricPill(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    private func actorCard(_ profile: MovieActorProfile) -> some View {
        VStack(spacing: 7) {
            AsyncImage(url: profile.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.cinemaAccent.opacity(0.72))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.08))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 72, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14), lineWidth: 0.7))

            Text(profile.name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 82)
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
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.48)).frame(width: 75, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "Đang cập nhật")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(value?.isEmpty == false ? 0.82 : 0.38))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5) }
    }
}

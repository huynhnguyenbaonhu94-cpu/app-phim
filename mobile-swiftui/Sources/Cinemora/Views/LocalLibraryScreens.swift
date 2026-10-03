import SwiftUI

struct WatchHistoryScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .lastTextBaseline) {
                        CinemaHeader(eyebrow: "LƯU TRÊN THIẾT BỊ", title: "LỊCH SỬ XEM")
                        Spacer()
                        if !store.localHistory.isEmpty {
                            Button("Xóa tất cả") { showClearAlert = true }
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                        }
                    }
                    if store.localHistory.isEmpty {
                        StateMessage(icon: "clock.arrow.circlepath", title: "Chưa có lịch sử xem", detail: "Các phim bạn bắt đầu xem sẽ xuất hiện ở đây.")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.localHistory) { record in
                                historyRow(record)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 58).padding(.bottom, 38)
            }
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
            .accessibilityLabel("Trở lại mục Lưu")
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Xóa toàn bộ lịch sử xem?", isPresented: $showClearAlert) {
            Button("Xóa tất cả", role: .destructive) { store.clearHistory() }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả lịch sử xem được lưu trên thiết bị sẽ bị xóa.")
        }
    }

    private func historyRow(_ record: LocalWatchRecord) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: ResumeMovieScreen(record: record)) {
                HStack(spacing: 12) {
                    PosterArt(url: record.movie.movie.posterURL)
                        .frame(width: 82, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.movie.name).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                        Text([record.episodeName, record.serverName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.58)).lineLimit(2)
                        if record.durationSeconds > 0 {
                            ProgressView(value: min(1, record.watchedSeconds / record.durationSeconds)).tint(Color.cinemaAccent)
                            Text("Đã xem \(formatTime(record.watchedSeconds)) / \(formatTime(record.durationSeconds))")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.52))
                        }
                        Text("Chạm để tiếp tục xem").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button { store.removeHistory(record) } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    .frame(width: 35, height: 35).background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Xóa khỏi lịch sử")
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 0.7))
    }

    private func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value)), hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

struct FavoritesScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .lastTextBaseline) {
                        CinemaHeader(eyebrow: "LƯU TRÊN THIẾT BỊ", title: "YÊU THÍCH")
                        Spacer()
                        if !store.localFavorites.isEmpty {
                            Button("Xóa tất cả") { showClearAlert = true }
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                        }
                    }
                    if store.localFavorites.isEmpty {
                        StateMessage(icon: "heart", title: "Chưa có phim yêu thích", detail: "Nhấn biểu tượng trái tim trong trang chi tiết để lưu phim.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.localFavorites.indices, id: \.self) { index in
                                favoriteCard(store.localFavorites[index])
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 58).padding(.bottom, 38)
            }
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
            .accessibilityLabel("Trở lại mục Lưu")
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Xóa toàn bộ yêu thích?", isPresented: $showClearAlert) {
            Button("Xóa tất cả", role: .destructive) { store.clearFavorites() }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Danh sách phim yêu thích trên thiết bị sẽ bị xóa.")
        }
    }

    private func favoriteCard(_ record: LocalMovieRecord) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: MovieDetailScreen(slug: record.slug)) {
                VStack(alignment: .leading, spacing: 8) {
                    PosterArt(url: record.movie.posterURL)
                        .aspectRatio(0.69, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    Text(record.name).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                    Text([record.originName, record.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.54)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Button { store.removeFavorite(record) } label: {
                Image(systemName: "heart.slash.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(.black.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain).padding(8).accessibilityLabel("Bỏ yêu thích")
        }
    }
}

struct SavedHubScreen: View {
    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionEyebrow(text: "LƯU TRÊN THIẾT BỊ")
                        Text("Lịch sử & Yêu thích")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Quản lý phim đang xem, phim yêu thích và gửi yêu cầu phim mới.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    savedDestination(icon: "clock.arrow.circlepath", title: "Lịch sử xem", detail: "Tiếp tục những bộ phim bạn đang xem", destination: WatchHistoryScreen())
                    savedDestination(icon: "heart.fill", title: "Yêu thích", detail: "Danh sách phim đã lưu", destination: FavoritesScreen())
                    savedDestination(icon: "slider.horizontal.3", title: "Cài đặt mặc định", detail: "Thiết lập cách phát video mỗi khi mở phim", destination: PlaybackDefaultsScreen())
                    savedDestination(icon: "textformat.size", title: "Tùy chỉnh phụ đề", detail: "Phông chữ, màu sắc, vị trí, viền và song ngữ", destination: SubtitlePreferencesScreen())
                    savedDestination(icon: "text.bubble.fill", title: "Yêu cầu phim", detail: "Gửi tên phim muốn Cinemora cập nhật", destination: MovieRequestScreen())
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 45)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func savedDestination<Destination: View>(icon: String, title: String, detail: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.cinemaAccent)
                    .frame(width: 42, height: 42)
                    .background(Color.cinemaAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(.white)
                    Text(detail).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(14)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.11), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

private enum DefaultStopTimer: String, CaseIterable, Identifiable {
    case off = "Tắt"
    case fifteen = "15 phút"
    case thirty = "30 phút"
    case sixty = "60 phút"
    case endOfEpisode = "Hết tập hiện tại"
    var id: String { rawValue }
}

struct PlaybackDefaultsScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(text: "LƯU TRÊN THIẾT BỊ")
                        Text("Cài đặt mặc định")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Các lựa chọn này sẽ được áp dụng mỗi khi bạn mở một trình phát mới.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    settingsCard
                }
                .padding(.horizontal, 20).padding(.top, 58).padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Label("Trở lại", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7))
            }
            .buttonStyle(.plain).padding(.leading, 20).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.playbackDefaults) { _, _ in store.savePlaybackDefaults() }
        .onDisappear { store.savePlaybackDefaults() }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            defaultToggle(icon: "forward.end.fill", title: "Tự động chuyển tập", detail: "Tự phát tập kế tiếp khi tập hiện tại kết thúc", value: Binding(get: { store.playbackDefaults.autoAdvanceEpisodes }, set: { store.playbackDefaults.autoAdvanceEpisodes = $0 }))
            Divider().overlay(.white.opacity(0.1))
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Color.cinemaAccent).frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hẹn giờ tắt").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    Text("Tự dừng video theo thời gian mặc định").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Picker("Hẹn giờ tắt", selection: Binding(get: { DefaultStopTimer(rawValue: store.playbackDefaults.stopTimer) ?? .off }, set: { store.playbackDefaults.stopTimer = $0.rawValue })) {
                    ForEach(DefaultStopTimer.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).tint(Color.cinemaAccent)
            }
            Divider().overlay(.white.opacity(0.1))
            defaultToggle(icon: "pip.enter", title: "Picture-in-Picture", detail: "Cho phép thu nhỏ video thành cửa sổ nổi khi rời app", value: Binding(get: { store.playbackDefaults.pictureInPicture }, set: { store.playbackDefaults.pictureInPicture = $0 }))
            Text("Bạn vẫn có thể thay đổi từng lựa chọn trong phần Cài đặt của trình phát.")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.46))
        }
        .padding(16)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
    }

    private func defaultToggle(icon: String, title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.cinemaAccent).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: value).labelsHidden().tint(Color.cinemaAccent)
        }
    }
}

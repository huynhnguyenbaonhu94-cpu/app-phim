import SwiftUI

// MARK: - Watch history

struct WatchHistoryScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline) {
                        CinemaHeader(eyebrow: "LƯU TRÊN TÀI KHOẢN", title: "LỊCH SỬ XEM")
                        Spacer()
                        if !store.localHistory.isEmpty {
                            Button {
                                showClearAlert = true
                            } label: {
                                Text("Xóa tất cả")
                                    .font(.auroraLabel(10, weight: .bold))
                                    .foregroundStyle(Color.auroraPink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.auroraPink.opacity(0.14)))
                                    .overlay(Capsule().strokeBorder(Color.auroraPink.opacity(0.3), lineWidth: 0.7))
                            }
                            .buttonStyle(.auroraPress(scale: 0.94))
                        }
                    }
                    .auroraReveal(0)

                    if store.accountUser == nil {
                        StateMessage(icon: "person.crop.circle.badge.exclamationmark", title: "Cần đăng nhập", detail: "Đăng nhập tài khoản để lưu và đồng bộ lịch sử xem trên các thiết bị.")
                    } else if store.localHistory.isEmpty {
                        StateMessage(icon: "clock.arrow.circlepath", title: "Chưa có lịch sử xem", detail: "Các phim bạn bắt đầu xem sẽ xuất hiện ở đây.")
                    } else {
                        ForEach(Array(store.localHistory.enumerated()), id: \.element.id) { index, record in
                            historyRow(record)
                                .auroraReveal(index % 10)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 120)
            }
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Trở lại") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Xóa toàn bộ lịch sử xem?", isPresented: $showClearAlert) {
            Button("Xóa tất cả", role: .destructive) { store.clearHistory() }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả lịch sử xem trong tài khoản sẽ bị xóa.")
        }
    }

    private func historyRow(_ record: LocalWatchRecord) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: ResumeMovieScreen(record: record)) {
                HStack(spacing: 13) {
                    PosterArt(url: record.movie.movie.posterURL)
                        .frame(width: 86, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.8)
                        }
                        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 7)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(record.movie.name)
                            .font(.auroraLabel(14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text([record.episodeName, record.serverName].compactMap { $0 }.joined(separator: " · "))
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .lineLimit(2)
                        if record.durationSeconds > 0 {
                            GeometryReader { proxy in
                                let progress = min(1, max(0, record.watchedSeconds / record.durationSeconds))
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.12))
                                    Capsule()
                                        .fill(LinearGradient.auroraPrimary)
                                        .frame(width: max(6, proxy.size.width * progress))
                                }
                            }
                            .frame(height: 5)
                            .padding(.trailing, 8)
                            Text("Đã xem \(formatTime(record.watchedSeconds)) / \(formatTime(record.durationSeconds))")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.auroraTextTertiary)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 8, weight: .black))
                            Text("Chạm để tiếp tục xem")
                        }
                        .font(.auroraLabel(9, weight: .bold))
                        .foregroundStyle(Color.auroraViolet)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.auroraPress(scale: 0.98))

            Button {
                withAnimation(Motion.sheet) { store.removeHistory(record) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .accessibilityLabel("Xóa khỏi lịch sử")
        }
        .padding(11)
        .auroraCard(cornerRadius: 22, tint: .auroraViolet, fill: 0.7)
    }

    private func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value)), hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Favorites

struct FavoritesScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline) {
                        CinemaHeader(eyebrow: "LƯU TRÊN TÀI KHOẢN", title: "YÊU THÍCH")
                        Spacer()
                        if !store.localFavorites.isEmpty {
                            Button {
                                showClearAlert = true
                            } label: {
                                Text("Xóa tất cả")
                                    .font(.auroraLabel(10, weight: .bold))
                                    .foregroundStyle(Color.auroraPink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.auroraPink.opacity(0.14)))
                                    .overlay(Capsule().strokeBorder(Color.auroraPink.opacity(0.3), lineWidth: 0.7))
                            }
                            .buttonStyle(.auroraPress(scale: 0.94))
                        }
                    }
                    .auroraReveal(0)

                    if store.accountUser == nil {
                        StateMessage(icon: "person.crop.circle.badge.exclamationmark", title: "Cần đăng nhập", detail: "Đăng nhập tài khoản để lưu và đồng bộ phim yêu thích trên các thiết bị.")
                    } else if store.localFavorites.isEmpty {
                        StateMessage(icon: "heart", title: "Chưa có phim yêu thích", detail: "Nhấn biểu tượng trái tim trong trang chi tiết để lưu phim.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(Array(store.localFavorites.enumerated()), id: \.element.id) { index, record in
                                favoriteCard(record, index: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 120)
            }
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Trở lại") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Xóa toàn bộ yêu thích?", isPresented: $showClearAlert) {
            Button("Xóa tất cả", role: .destructive) { store.clearFavorites() }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Danh sách phim yêu thích trong tài khoản sẽ bị xóa.")
        }
    }

    private func favoriteCard(_ record: LocalMovieRecord, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: MovieDetailScreen(slug: record.slug)) {
                VStack(alignment: .leading, spacing: 9) {
                    PosterArt(url: record.movie.posterURL)
                        .aspectRatio(0.69, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            if let quality = record.quality, !quality.isEmpty {
                                Text(quality.uppercased())
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.auroraVoid)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(LinearGradient.auroraPrimary))
                                    .padding(9)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                        }
                        .shadow(color: Color.black.opacity(0.38), radius: 12, y: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.name)
                            .font(.auroraLabel(13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text([record.originName, record.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraTextTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.auroraPress(scale: 0.97))

            Button {
                withAnimation(Motion.sheet) { store.removeFavorite(record) }
            } label: {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .padding(9)
            .accessibilityLabel("Bỏ yêu thích")
        }
        .auroraReveal(index % 10)
    }
}

// MARK: - Saved hub

struct SavedHubScreen: View {
    @Environment(CinemaStore.self) private var store
    @State private var pressedDestination: String?

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: "LƯU TRÊN TÀI KHOẢN")
                        AuroraGradientText(text: "Lịch sử & Yêu thích", font: .auroraDisplay(28))
                        Text("Đăng nhập để lưu lịch sử xem và phim yêu thích; các cài đặt khác vẫn dùng được khi offline.")
                            .font(.auroraBody(12))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 18)
                    .auroraReveal(0)

                    accountCard
                        .auroraReveal(1)

                    savedDestination(icon: "person.crop.circle.fill", title: "Tài khoản & thiết bị", detail: "Đăng nhập, đồng bộ thư viện và quản lý tối đa 5 thiết bị", tint: .auroraViolet, index: 2, destination: AccountSettingsScreen())
                    savedDestination(icon: "clock.arrow.circlepath", title: "Lịch sử xem", detail: "Tiếp tục những bộ phim bạn đang xem", tint: .auroraSky, index: 3, destination: WatchHistoryScreen())
                    savedDestination(icon: "heart.fill", title: "Yêu thích", detail: "Danh sách phim đã lưu", tint: .auroraPink, index: 4, destination: FavoritesScreen())
                    savedDestination(icon: "slider.horizontal.3", title: "Cài đặt mặc định", detail: "Thiết lập cách phát video mỗi khi mở phim", tint: .auroraMint, index: 5, destination: PlaybackDefaultsScreen())
                    savedDestination(icon: "textformat.size", title: "Tùy chỉnh phụ đề", detail: "Phông chữ, màu sắc, vị trí, nền và viền", tint: .auroraAmber, index: 6, destination: SubtitlePreferencesScreen())
                    savedDestination(icon: "text.bubble.fill", title: "Yêu cầu phim", detail: "Gửi tên phim muốn Cinemora cập nhật", tint: .auroraViolet, index: 7, destination: MovieRequestScreen())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var accountCard: some View {
        NavigationLink(destination: AccountSettingsScreen()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.auroraPrimary)
                        .frame(width: 52, height: 52)
                        .auroraHalo(.auroraViolet, radius: 16, opacity: 0.45)
                    Image(systemName: store.accountUser == nil ? "person.fill" : "checkmark")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color.auroraVoid)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.accountUser?.displayName ?? "Chưa đăng nhập")
                        .font(.auroraLabel(15, weight: .black))
                        .foregroundStyle(.white)
                    Text(store.accountUser?.email ?? "Đăng nhập để đồng bộ lịch sử và yêu thích")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(15)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.auroraPress(scale: 0.98))
        .auroraCard(cornerRadius: 24, tint: .auroraViolet, glow: true)
    }

    private func savedDestination<Destination: View>(icon: String, title: String, detail: String, tint: Color, index: Int, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.auroraLabel(14, weight: .black))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
        .buttonStyle(.auroraPress(scale: 0.98))
        .auroraCard(cornerRadius: 21, tint: tint, fill: 0.65)
        .scaleEffect(pressedDestination == title ? 0.975 : 1)
        .opacity(pressedDestination == title ? 0.82 : 1)
        .animation(.easeOut(duration: 0.12), value: pressedDestination)
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.easeOut(duration: 0.12)) { pressedDestination = title }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.18)) { if pressedDestination == title { pressedDestination = nil } }
            }
        })
        .auroraReveal(index)
    }
}

// MARK: - Playback defaults

private enum DefaultStopTimer: String, CaseIterable, Identifiable {
    case off = "Tắt"
    case fifteen = "15 phút"
    case thirty = "30 phút"
    case sixty = "60 phút"
    case endOfEpisode = "Hết tập hiện tại"
    var id: String { rawValue }
}

struct PlaybackDefaultsScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionEyebrow(text: "LƯU TRÊN THIẾT BỊ")
                        AuroraGradientText(text: "Cài đặt mặc định", font: .auroraDisplay(27))
                        Text("Các lựa chọn này sẽ được áp dụng mỗi khi bạn mở một trình phát mới.")
                            .font(.auroraBody(12))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                    .auroraReveal(0)

                    settingsCard
                        .auroraReveal(1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 120)
            }
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Trở lại") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.playbackDefaults) { _, _ in store.savePlaybackDefaults() }
        .onDisappear { store.savePlaybackDefaults() }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            defaultToggle(icon: "forward.end.fill", title: "Tự động chuyển tập", detail: "Tự phát tập kế tiếp khi tập hiện tại kết thúc", tint: .auroraViolet, value: Binding(get: { store.playbackDefaults.autoAdvanceEpisodes }, set: { store.playbackDefaults.autoAdvanceEpisodes = $0 }))
            Divider().overlay(Color.white.opacity(0.09))
            HStack(spacing: 11) {
                settingIcon("moon.zzz.fill", tint: .auroraSky)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hẹn giờ tắt")
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Tự dừng video theo thời gian mặc định")
                        .font(.auroraBody(9))
                        .foregroundStyle(Color.auroraTextTertiary)
                }
                Spacer()
                Picker("Hẹn giờ tắt", selection: Binding(get: { DefaultStopTimer(rawValue: store.playbackDefaults.stopTimer) ?? .off }, set: { store.playbackDefaults.stopTimer = $0.rawValue })) {
                    ForEach(DefaultStopTimer.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.auroraViolet)
            }
            Divider().overlay(Color.white.opacity(0.09))
            defaultToggle(icon: "pip.enter", title: "Picture-in-Picture", detail: "Cho phép thu nhỏ video thành cửa sổ nổi khi rời app", tint: .auroraMint, value: Binding(get: { store.playbackDefaults.pictureInPicture }, set: { store.playbackDefaults.pictureInPicture = $0 }))
            Text("Bạn vẫn có thể thay đổi từng lựa chọn trong phần Cài đặt của trình phát.")
                .font(.auroraBody(9))
                .foregroundStyle(Color.auroraTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .auroraCard(cornerRadius: 24, tint: .auroraViolet, fill: 0.7)
    }

    private func settingIcon(_ symbol: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 34, height: 34)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func defaultToggle(icon: String, title: String, detail: String, tint: Color, value: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            settingIcon(icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.auroraBody(9))
                    .foregroundStyle(Color.auroraTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: value).labelsHidden().tint(Color.auroraViolet)
        }
    }
}

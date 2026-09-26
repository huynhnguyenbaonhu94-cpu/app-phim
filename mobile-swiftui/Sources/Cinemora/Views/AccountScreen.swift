import SwiftUI

struct AccountScreen: View {
    @State private var user: AccountUser?
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var registerMode = false
    @State private var favorites: [FavoriteMovie] = []
    @State private var history: [WatchHistoryItem] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var accountMessage: String?
    private let api = CinemaAPI.shared

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "CINEMORA · CÁ NHÂN HÓA", title: "TÀI KHOẢN")
                    if let user {
                        signedInView(user)
                    } else {
                        authView
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 38)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadSession() }
        .onAppear { if user != nil { Task { await loadAccountData() } } }
        .alert("Tài khoản", isPresented: Binding(get: { accountMessage != nil }, set: { if !$0 { accountMessage = nil } })) {
            Button("Đóng", role: .cancel) { accountMessage = nil }
        } message: { Text(accountMessage ?? "") }
    }

    private var authView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: registerMode ? "person.badge.plus" : "person.crop.circle.fill")
                .font(.system(size: 34, weight: .light)).foregroundStyle(Color.cinemaAccent)
                .frame(width: 64, height: 64).background(Color.cinemaAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 23))
            Text(registerMode ? "Tạo tài khoản" : "Đăng nhập").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text(registerMode ? "Lưu lịch sử xem và phim yêu thích trên mọi thiết bị." : "Đăng nhập để đồng bộ lịch sử xem và danh sách yêu thích.")
                .font(.system(size: 13)).lineSpacing(4).foregroundStyle(.white.opacity(0.62))
            if registerMode { TextField("Tên hiển thị", text: $name).textContentType(.name).authField() }
            TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).textContentType(.emailAddress).authField()
            SecureField("Mật khẩu", text: $password).textContentType(registerMode ? .newPassword : .password).authField()
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red.opacity(0.9)) }
            Button { Task { await submitAuth() } } label: {
                HStack { if loading { ProgressView().tint(Color.cinemaInk) }; Text(registerMode ? "Đăng ký" : "Đăng nhập") }
                    .font(.system(size: 13, weight: .black)).foregroundStyle(Color.cinemaInk).frame(maxWidth: .infinity).padding(.vertical, 13).background(Color.cinemaAccent, in: Capsule())
            }.buttonStyle(.plain).disabled(loading)
            Button { registerMode.toggle(); errorMessage = nil } label: {
                Text(registerMode ? "Đã có tài khoản? Đăng nhập" : "Chưa có tài khoản? Đăng ký ngay")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.cinemaAccent).frame(maxWidth: .infinity)
            }.buttonStyle(.plain)
        }
        .padding(22).cinemaGlass(in: RoundedRectangle(cornerRadius: 28), tint: .white.opacity(0.06))
    }

    private func signedInView(_ account: AccountUser) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 40)).foregroundStyle(Color.cinemaAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name ?? "Người dùng").font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(.white)
                    Text(account.email ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button { Task { await signOut() } } label: { Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.white.opacity(0.7)) }.buttonStyle(.plain).accessibilityLabel("Đăng xuất")
            }
            .padding(18).cinemaGlass(in: RoundedRectangle(cornerRadius: 22), tint: .white.opacity(0.06))
            SectionHeading(eyebrow: "ĐÃ LƯU", title: "Phim yêu thích")
            if favorites.isEmpty { emptyRow("Chưa có phim yêu thích", icon: "heart") }
            else { ForEach(favorites) { item in favoriteRow(item) } }
            SectionHeading(eyebrow: "GẦN ĐÂY", title: "Lịch sử xem")
            if history.isEmpty { emptyRow("Chưa có lịch sử xem", icon: "clock") }
            else { ForEach(history) { item in historyRow(item) } }
        }
    }

    private func favoriteRow(_ item: FavoriteMovie) -> some View {
        HStack(spacing: 8) {
            NavigationLink { MovieDetailScreen(slug: item.movieSlug) } label: { itemContent(title: item.movieName, subtitle: item.year.map { String($0) } ?? "Phim", icon: "heart.fill") }
            deleteButton { await deleteFavorite(item) }
        }
    }

    private func historyRow(_ item: WatchHistoryItem) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                MovieDetailScreen(slug: item.movieSlug, initialEpisodeSlug: item.episodeSlug, initialSourceName: item.sourceName, resumeSeconds: item.watchedSeconds, autoPlay: true)
            } label: {
                itemContent(title: item.movieName, subtitle: "\(item.episodeName ?? "Phim") · \(item.sourceName ?? "Nguồn mặc định") · \(formatProgress(item))", icon: "clock.arrow.circlepath")
            }
            deleteButton { await deleteHistory(item) }
        }
    }

    private func itemContent(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.cinemaAccent).frame(width: 38, height: 38).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).lineLimit(1); Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(2) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.28))
        }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func deleteButton(action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: { Image(systemName: "trash").font(.system(size: 12, weight: .bold)).foregroundStyle(.red.opacity(0.85)).frame(width: 42, height: 50).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)) }
            .buttonStyle(.plain).accessibilityLabel("Xóa")
    }

    private func formatProgress(_ item: WatchHistoryItem) -> String {
        guard item.durationSeconds > 0 else { return "Đã lưu" }
        return "\(Int(Double(item.watchedSeconds) / Double(item.durationSeconds) * 100))%"
    }

    private func deleteFavorite(_ item: FavoriteMovie) async {
        do {
            try await api.removeFavorite(slug: item.movieSlug)
            favorites.removeAll { $0.id == item.id }
        } catch { accountMessage = error.localizedDescription }
    }

    private func deleteHistory(_ item: WatchHistoryItem) async {
        do {
            try await api.removeHistory(id: item.id)
            history.removeAll { $0.id == item.id }
            clearLocalHistoryTombstone(item.id)
        } catch APIError.procedureUnavailable {
            saveLocalHistoryTombstone(item.id)
            history.removeAll { $0.id == item.id }
        } catch { accountMessage = error.localizedDescription }
    }

    private func emptyRow(_ text: String, icon: String) -> some View { Label(text, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 15)) }

    private func loadSession() async {
        guard let account = try? await api.me() else { return }
        await MainActor.run { user = account }
        await loadAccountData()
    }

    private func submitAuth() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else { errorMessage = "Vui lòng nhập email hợp lệ."; return }
        guard password.count >= 8 else { errorMessage = "Mật khẩu phải có ít nhất 8 ký tự."; return }
        if registerMode && cleanName.count < 2 { errorMessage = "Tên hiển thị phải có ít nhất 2 ký tự."; return }
        loading = true
        do {
            let account = registerMode ? try await api.register(name: cleanName, email: cleanEmail, password: password) : try await api.login(email: cleanEmail, password: password)
            await MainActor.run { user = account; password = "" }
            await loadAccountData()
        } catch { errorMessage = error.localizedDescription }
        loading = false
    }

    private func loadAccountData() async {
        async let saved = api.favorites()
        async let watched = api.history()
        if let values = try? await saved { favorites = values }
        if let values = try? await watched { history = values.filter { !localHistoryTombstones.contains($0.id) } }
    }

    private func signOut() async {
        try? await api.logout()
        user = nil; favorites = []; history = []
    }

    private var localHistoryTombstones: Set<Int> {
        Set(UserDefaults.standard.array(forKey: "cinemora.deletedHistoryIDs") as? [Int] ?? [])
    }

    private func saveLocalHistoryTombstone(_ id: Int) {
        var values = localHistoryTombstones
        values.insert(id)
        UserDefaults.standard.set(Array(values), forKey: "cinemora.deletedHistoryIDs")
        accountMessage = "Đã ẩn mục này trên thiết bị. Máy chủ hiện tại chưa hỗ trợ đồng bộ thao tác xóa lịch sử."
    }

    private func clearLocalHistoryTombstone(_ id: Int) {
        var values = localHistoryTombstones
        values.remove(id)
        UserDefaults.standard.set(Array(values), forKey: "cinemora.deletedHistoryIDs")
    }
}

private extension View {
    func authField() -> some View {
        self.font(.system(size: 13)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 13).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

import SwiftUI

/// Khối bình luận trong trang chi tiết phim.
///
/// Chỉ thành viên đã đăng nhập mới gửi được bình luận. Gửi theo kiểu lạc quan nên
/// nội dung hiện ngay, và bình luận của người khác tự xuất hiện nhờ nhịp làm mới
/// trong lúc màn hình còn mở.
struct CommentsSection: View {
    let movie: Movie

    @Environment(CinemaStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var comments = CommentsStore()
    @State private var draft = ""
    @State private var replyTarget: MovieComment?
    @State private var showLoginPrompt = false
    @State private var showLogin = false
    @State private var pendingDelete: MovieComment?
    @State private var sentPulse = 0
    @FocusState private var composerFocused: Bool

    private var author: CommentAuthor {
        store.accountUser.map { CommentAuthor(account: $0) } ?? .guest
    }

    private var isSignedIn: Bool { store.accountUser != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isSignedIn {
                composer
            } else {
                loginCallout
            }

            if comments.isLocalOnly && comments.totalCount > 0 {
                localNotice
            }

            content
        }
        .auroraReveal(4)
        .sensoryFeedback(.success, trigger: sentPulse)
        .task(id: movie.slug) { comments.start(slug: movie.slug, author: author) }
        .onDisappear { comments.stop() }
        .onChange(of: store.accountUser?.id) { _, _ in
            // Đăng nhập xong thì nạp lại với tư cách thành viên.
            comments.start(slug: movie.slug, author: author)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await comments.refresh(author: author) } }
        }
        .alert("Cần đăng nhập", isPresented: $showLoginPrompt) {
            Button("Đăng nhập") { showLogin = true }
            Button("Để sau", role: .cancel) { }
        } message: {
            Text("Bạn cần đăng nhập để bình luận và trả lời bình luận của người khác.")
        }
        .sheet(isPresented: $showLogin) {
            AccountSettingsScreen()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Xoá bình luận này?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                if let target = pendingDelete { comments.delete(target, author: author) }
                pendingDelete = nil
            }
            Button("Huỷ", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Bình luận sẽ bị xoá khỏi phim này.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            SectionHeading(eyebrow: "CỘNG ĐỒNG", title: "Bình luận")
            Spacer(minLength: 8)
            if comments.totalCount > 0 {
                Text("\(comments.totalCount)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Color.auroraVoid)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.auroraPrimary))
                    .contentTransition(.numericText())
                    .animation(Motion.gentle, value: comments.totalCount)
            }
        }
    }

    // MARK: - Chưa đăng nhập

    private var loginCallout: some View {
        Button {
            showLoginPrompt = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.auroraViolet)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.auroraViolet.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đăng nhập để bình luận")
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Chỉ thành viên mới gửi được bình luận và trả lời.")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color.auroraTextTertiary)
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.auroraPress(scale: 0.98))
        .auroraCard(cornerRadius: 20, tint: .auroraViolet, fill: 0.7)
    }

    // MARK: - Ô soạn

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let replyTarget {
                HStack(spacing: 7) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 9, weight: .black))
                    Text("Đang trả lời \(replyTarget.authorName)")
                        .font(.auroraLabel(10, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(Motion.tap) { self.replyTarget = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Huỷ trả lời")
                }
                .foregroundStyle(Color.auroraViolet)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(replyTarget == nil ? "Viết bình luận của bạn…" : "Viết trả lời…")
                            .font(.auroraBody(13))
                            .foregroundStyle(Color.auroraTextTertiary)
                            .padding(.top, 9)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .font(.auroraBody(13))
                        .foregroundStyle(.white)
                        .tint(Color.auroraViolet)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.sentences)
                        .focused($composerFocused)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 5)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minHeight: 46, alignment: .top)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.auroraViolet.opacity(composerFocused ? 0.55 : 0.16), lineWidth: 1)
                }
                .animation(Motion.gentle, value: composerFocused)

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(canSend ? Color.auroraVoid : Color.white.opacity(0.35))
                        .frame(width: 46, height: 46)
                        .background {
                            if canSend {
                                Circle().fill(LinearGradient.auroraPrimary)
                            } else {
                                Circle().fill(Color.white.opacity(0.07))
                            }
                        }
                }
                .buttonStyle(.auroraPress(scale: 0.92))
                .disabled(!canSend)
                .accessibilityLabel("Gửi bình luận")
            }
        }
        .padding(14)
        .auroraCard(cornerRadius: 22, tint: .auroraViolet, fill: 0.75)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isSignedIn
    }

    private func send() {
        let text = draft
        guard comments.send(text, replyingTo: replyTarget, author: author) else { return }
        withAnimation(Motion.tap) {
            draft = ""
            replyTarget = nil
            composerFocused = false
        }
        sentPulse += 1
    }

    private var localNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(size: 10, weight: .bold))
            Text("Máy chủ chưa bật bình luận, nội dung đang được lưu trên thiết bị này.")
                .font(.auroraBody(10))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.auroraTextTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var content: some View {
        if comments.isLoading && !comments.loadedOnce {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(.auroraViolet)
                    Text("Đang tải bình luận…")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
            }
            .padding(.vertical, 6)
        } else if let error = comments.error, comments.totalCount == 0 {
            StateMessage(icon: "bubble.left.and.exclamationmark.bubble.right", title: "Chưa tải được bình luận", detail: error, actionTitle: "Thử lại") {
                Task { await comments.refresh(author: author) }
            }
        } else if comments.totalCount == 0 {
            StateMessage(icon: "bubble.left.and.bubble.right", title: "Chưa có bình luận", detail: isSignedIn ? "Hãy là người đầu tiên chia sẻ cảm nhận về phim này." : "Đăng nhập để là người đầu tiên bình luận về phim này.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(comments.threads) { thread in
                    VStack(alignment: .leading, spacing: 12) {
                        commentRow(thread.root, isReply: false)
                        if !thread.replies.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(thread.replies) { reply in
                                    commentRow(reply, isReply: true)
                                }
                            }
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: MovieComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: isReply ? 9 : 11) {
            avatar(comment, isReply: isReply)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    nameLabel(comment)
                    if comment.isAdmin { AdminBadge() }
                    if comment.isMine && !comment.isAdmin {
                        Text("BẠN")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(Color.auroraViolet)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.auroraViolet.opacity(0.16)))
                    }
                    Spacer(minLength: 6)
                    Text(comment.relativeTime)
                        .font(.auroraBody(9))
                        .foregroundStyle(Color.auroraTextTertiary)
                }

                Text(comment.content)
                    .font(.auroraBody(12.5))
                    .foregroundStyle(comment.isPending ? Color.white.opacity(0.55) : Color.auroraTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    if comment.isPending {
                        statusChip(text: "Đang gửi…", icon: "arrow.up.circle", tint: Color.auroraTextTertiary)
                    } else if comment.isFailed {
                        Button {
                            comments.retry(comment, author: author)
                        } label: {
                            statusChip(text: "Gửi lỗi — thử lại", icon: "arrow.clockwise", tint: Color.auroraAmber)
                        }
                        .buttonStyle(.plain)
                    } else {
                        if comment.isLocal {
                            statusChip(text: "Trên thiết bị", icon: "iphone", tint: Color.auroraTextTertiary)
                        }
                        if isSignedIn {
                            Button {
                                withAnimation(Motion.tap) {
                                    replyTarget = comment
                                    composerFocused = true
                                }
                            } label: {
                                Text("Trả lời")
                                    .font(.auroraLabel(10, weight: .semibold))
                                    .foregroundStyle(Color.auroraTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if comment.isMine && !comment.isPending {
                        Button {
                            pendingDelete = comment
                        } label: {
                            Text("Xoá")
                                .font(.auroraLabel(10, weight: .semibold))
                                .foregroundStyle(Color.auroraTextTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func avatar(_ comment: MovieComment, isReply: Bool) -> some View {
        let size: CGFloat = isReply ? 26 : 34
        if let image = AvatarImageCache.image(for: comment.avatar) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                .opacity(comment.isPending ? 0.6 : 1)
                .accessibilityLabel("Ảnh đại diện của \(comment.authorName)")
        } else {
            initialsAvatar(comment, size: size)
        }
    }

    @ViewBuilder
    private func initialsAvatar(_ comment: MovieComment, size: CGFloat) -> some View {
        Text(comment.initials)
            .font(.system(size: max(10, size * 0.42), weight: .black, design: .rounded))
            .foregroundStyle(comment.isAdmin ? .white : Color.auroraVoid)
            .frame(width: size, height: size)
            .background {
                if comment.isAdmin {
                    Circle().fill(LinearGradient(
                        colors: [Color(red: 0.29, green: 0.63, blue: 1.0), Color(red: 0.09, green: 0.40, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                } else {
                    Circle().fill(LinearGradient.auroraPrimary)
                }
            }
            .opacity(comment.isPending ? 0.6 : 1)
    }

    @ViewBuilder
    private func nameLabel(_ comment: MovieComment) -> some View {
        HStack(spacing: 6) {
            if comment.isAdmin {
                // Tên của quản trị viên phải nổi bật giữa danh sách.
                Text(comment.displayName)
                    .font(.auroraLabel(12, weight: .heavy))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 0.44, green: 0.72, blue: 1.0), Color(red: 0.16, green: 0.48, blue: 1.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .lineLimit(1)
            } else {
                Text(comment.displayName)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(comment.isMine ? Color.auroraViolet : Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            if comment.isPinned {
                statusChip(text: "ĐÃ GHIM", icon: "pin.fill", tint: Color.auroraSky)
            }
        }
    }

    private func statusChip(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text).font(.auroraLabel(9, weight: .semibold))
        }
        .foregroundStyle(tint)
    }
}

// MARK: - Huy hiệu quản trị

/// Tích xanh động cho tài khoản quản trị.
///
/// Chuyển động chỉ dùng `scaleEffect` và một quầng sáng nhỏ trên một hình 17pt, và
/// tự tắt khi bật *Reduce Motion* — quầng sáng lặp vô hạn trên cả danh sách là đúng
/// thứ từng làm app giật trước đây.
struct AdminBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private static let blue = Color(red: 0.20, green: 0.55, blue: 1.0)
    private static let blueDeep = Color(red: 0.09, green: 0.40, blue: 0.94)

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Self.blue, Self.blueDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                    }
                    .shadow(color: Self.blue.opacity(pulse ? 0.55 : 0.22), radius: pulse ? 6 : 3)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
            }
            .scaleEffect(pulse ? 1.08 : 1)

            Text("ADMIN")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Self.blue)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Self.blue.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Self.blue.opacity(0.35), lineWidth: 0.8))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Quản trị viên")
    }
}
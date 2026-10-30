import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SpecialAccountChatScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var messages: [RemoteSpecialChatMessage] = []
    @State private var loadedUserID: Int?
    @State private var draft = ""
    @State private var pendingTextRequestID: String?
    @State private var pendingTextValue: String?
    @State private var selectedMedia: PhotosPickerItem?
    @State private var isLoading = true
    @State private var isSending = false
    @State private var isUploading = false
    @State private var errorNote: String?
    @State private var actionErrorVisible = false
    @State private var pendingMedia: PendingSpecialChatMedia?
    @State private var mediaViewer: SpecialChatMediaViewerItem?
    @FocusState private var composerFocused: Bool

    private let api = CinemaAPI.shared

    var body: some View {
        ZStack {
            CinemaBackground()
            VStack(spacing: 0) {
                header
                if isLoading && messages.isEmpty {
                    loadingView
                } else if messages.isEmpty {
                    emptyView
                } else {
                    messageList
                }
                if errorNote != nil || pendingMedia != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        if let errorNote {
                            Text(errorNote)
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraPink)
                        }
                        if pendingMedia != nil {
                            Button { Task { await retryPendingMedia() } } label: {
                                Label("Thử gửi lại tệp", systemImage: "arrow.clockwise")
                                    .font(.auroraLabel(9, weight: .bold))
                                    .foregroundStyle(Color.auroraAccent)
                            }
                            .disabled(isSending || isUploading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 5)
                }
                composer
            }
        }
        .navigationTitle("Chat với admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Đóng") { dismiss() }
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(Color.auroraAccent)
            }
        }
        .task(id: chatTaskKey) {
            guard let account = store.accountUser, account.hasSpecialPrivileges else {
                messages = []
                loadedUserID = nil
                pendingMedia = nil
                draft = ""
                isLoading = false
                actionErrorVisible = false
                errorNote = "Tài khoản chưa được cấp quyền sử dụng chat đặc biệt."
                return
            }
            if loadedUserID != account.id {
                messages = []
                loadedUserID = account.id
                pendingMedia = nil
                draft = ""
                isLoading = true
                actionErrorVisible = false
            }
            await refreshMessages(initial: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { await refreshMessages(initial: false) }
            }
        }
        .onChange(of: selectedMedia) { _, item in
            guard let item else { return }
            Task { await sendPickedMedia(item) }
        }
        .fullScreenCover(item: $mediaViewer) { viewer in
            Group {
                switch viewer.content {
                case .image(let image): SpecialChatImageViewer(image: image)
                case .video(let fileURL): SpecialChatVideoPlayerSheet(fileURL: fileURL)
                }
            }
            .preferredColorScheme(.dark)
        }
        .overlay {
            if !connectivity.isConnected {
                NetworkUnavailableOverlay()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.auroraViolet.opacity(0.18)).frame(width: 39, height: 39)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.auroraViolet)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Quản trị viên Cinemora")
                    .font(.auroraLabel(12, weight: .black))
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    LivePulse(color: .auroraMint, size: 5, animated: false)
                    Text("Cuộc trò chuyện riêng · tự cập nhật")
                        .font(.auroraBody(9))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.auroraMint)
                .accessibilityLabel("Cuộc trò chuyện được bảo vệ theo tài khoản")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.auroraInk.opacity(0.74))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            let rowWidth = max(280, geometry.size.width - 28)
                            let bubbleWidth = min(420, rowWidth * 0.82)
                            SpecialChatMessageBubble(
                                message: message,
                                maxBubbleWidth: bubbleWidth,
                                maxMediaWidth: max(140, bubbleWidth - 24)
                            ) { fileURL in
                                mediaViewer = SpecialChatMediaViewerItem(content: .video(fileURL))
                            } onViewImage: { image in
                                mediaViewer = SpecialChatMediaViewerItem(content: .image(image))
                            }
                            .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("special-chat-bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 15)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    guard !reduceMotion else {
                        proxy.scrollTo("special-chat-bottom", anchor: .bottom)
                        return
                    }
                    withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("special-chat-bottom", anchor: .bottom) }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 13) {
            ProgressView().tint(Color.auroraViolet).scaleEffect(1.15)
            Text("Đang tải cuộc trò chuyện…")
                .font(.auroraBody(11))
                .foregroundStyle(Color.auroraTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.auroraViolet)
            Text("Bắt đầu trò chuyện")
                .font(.auroraLabel(14, weight: .black))
                .foregroundStyle(.white)
            Text("Tin nhắn chỉ hiển thị với tài khoản của bạn và quản trị viên.")
                .font(.auroraBody(11))
                .foregroundStyle(Color.auroraTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            PhotosPicker(selection: $selectedMedia, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                Image(systemName: isUploading ? "hourglass" : "paperclip")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isUploading ? Color.auroraTextTertiary : Color.auroraSky)
                    .frame(width: 42, height: 42)
                    .background(Color.auroraSky.opacity(0.10), in: Circle())
                    .overlay(Circle().strokeBorder(Color.auroraSky.opacity(0.20), lineWidth: 0.8))
            }
            .disabled(isSending || isUploading || pendingMedia != nil || store.accountUser?.hasSpecialPrivileges != true)
            .accessibilityLabel("Chọn ảnh hoặc video đính kèm")

            TextField("Nhắn tin cho admin…", text: $draft, axis: .vertical)
                .font(.auroraBody(12))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.auroraRaised.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
                .disabled(isUploading || isSending || pendingMedia != nil)

            Button { Task { await sendText() } } label: {
                Image(systemName: isSending ? "hourglass" : "arrow.up")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.auroraVoid)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient.auroraPrimary, in: Circle())
                    .opacity(canSend ? 1 : 0.48)
            }
            .buttonStyle(.auroraPress(scale: 0.92))
            .disabled(!canSend || isUploading)
            .accessibilityLabel("Gửi tin nhắn")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.auroraVoid.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && pendingMedia == nil && store.accountUser?.hasSpecialPrivileges == true
    }

    private var chatTaskKey: String {
        "\(store.accountUser?.id ?? 0)-\(store.accountUser?.hasSpecialPrivileges == true)"
    }

    @MainActor
    private func refreshMessages(initial: Bool) async {
        do {
            let incoming = try await api.specialChatMessages(afterId: initial ? nil : messages.last?.id)
            if initial {
                messages = incoming
            } else if !incoming.isEmpty {
                let known = Set(messages.map(\.id))
                messages.append(contentsOf: incoming.filter { !known.contains($0.id) })
            }
            if !actionErrorVisible { errorNote = nil }
            isLoading = false
        } catch {
            isLoading = false
            if !actionErrorVisible {
                errorNote = messages.isEmpty ? "Không tải được tin nhắn. Hãy thử lại khi mạng ổn định." : "Chưa đồng bộ được tin nhắn mới. Đang tiếp tục thử lại…"
            }
        }
    }

    @MainActor
    private func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, !isUploading, pendingMedia == nil else { return }
        if pendingTextValue != text {
            pendingTextValue = text
            pendingTextRequestID = UUID().uuidString
        }
        let requestID = pendingTextRequestID ?? UUID().uuidString
        pendingTextRequestID = requestID
        isSending = true
        actionErrorVisible = false
        errorNote = nil
        defer { isSending = false }
        do {
            let message = try await api.sendSpecialChatMessage(text: text, attachmentId: nil, clientRequestId: requestID)
            draft = ""
            pendingTextRequestID = nil
            pendingTextValue = nil
            append(message)
            composerFocused = true
        } catch {
            actionErrorVisible = true
            errorNote = friendlySpecialChatError(error, operation: .text)
        }
    }

    @MainActor
    private func sendPickedMedia(_ item: PhotosPickerItem) async {
        selectedMedia = nil
        guard !isUploading, pendingMedia == nil, let ownerUserID = store.accountUser?.id, store.accountUser?.hasSpecialPrivileges == true else { return }
        isUploading = true
        actionErrorVisible = false
        errorNote = nil
        defer { isUploading = false }
        do {
            guard let original = try await item.loadTransferable(type: Data.self), !original.isEmpty else {
                throw SpecialChatClientError.invalidFile
            }
            let contentType = item.supportedContentTypes.first
            let prepared = try prepareMedia(original, contentType: contentType)
            let uploaded = try await api.uploadSpecialChatMedia(data: prepared.data, filename: prepared.filename, mimeType: prepared.mimeType)
            guard store.accountUser?.id == ownerUserID, store.accountUser?.hasSpecialPrivileges == true else {
                actionErrorVisible = true
                errorNote = "Tài khoản đã thay đổi trong lúc tải tệp; tệp chưa được gửi."
                return
            }
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let pending = PendingSpecialChatMedia(attachmentId: uploaded.attachmentId, userID: ownerUserID, text: text.isEmpty ? nil : text, clientRequestID: UUID().uuidString)
            pendingMedia = pending
            let message = try await api.sendSpecialChatMessage(text: pending.text, attachmentId: pending.attachmentId, clientRequestId: pending.clientRequestID)
            pendingMedia = nil
            draft = ""
            pendingTextRequestID = nil
            pendingTextValue = nil
            append(message)
        } catch {
            actionErrorVisible = true
            errorNote = friendlySpecialChatError(error, operation: .media)
        }
    }

    @MainActor
    private func retryPendingMedia() async {
        guard let pending = pendingMedia, !isSending, !isUploading else { return }
        guard pending.userID == store.accountUser?.id, store.accountUser?.hasSpecialPrivileges == true else {
            pendingMedia = nil
            errorNote = "Tài khoản đã thay đổi; hãy chọn lại tệp trong tài khoản được cấp quyền."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await api.sendSpecialChatMessage(text: pending.text, attachmentId: pending.attachmentId, clientRequestId: pending.clientRequestID)
            pendingMedia = nil
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == (pending.text ?? "") { draft = "" }
            actionErrorVisible = false
            errorNote = nil
            append(message)
        } catch {
            actionErrorVisible = true
            errorNote = friendlySpecialChatError(error, operation: .media)
        }
    }

    @MainActor
    private func append(_ message: RemoteSpecialChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
    }

    private func prepareMedia(_ data: Data, contentType: UTType?) throws -> (data: Data, filename: String, mimeType: String) {
        if contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .video) == true {
            let mime = contentType?.preferredMIMEType ?? "video/mp4"
            guard ["video/mp4", "video/quicktime"].contains(mime) else { throw SpecialChatClientError.unsupportedVideo }
            guard data.count <= 32 * 1024 * 1024 else { throw SpecialChatClientError.videoTooLarge }
            let ext = contentType?.preferredFilenameExtension ?? (mime == "video/quicktime" ? "mov" : "mp4")
            return (data, "video.\(ext)", mime)
        }

        if contentType?.preferredMIMEType == "image/gif" {
            guard data.count <= 8 * 1024 * 1024 else { throw SpecialChatClientError.imageTooLarge }
            return (data, "image.gif", "image/gif")
        }
        guard let image = UIImage(data: data) else { throw SpecialChatClientError.invalidFile }
        let maxDimension: CGFloat = 1800
        let factor = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * factor), height: max(1, image.size.height * factor))
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.82) else { throw SpecialChatClientError.invalidFile }
        guard jpeg.count <= 8 * 1024 * 1024 else { throw SpecialChatClientError.imageTooLarge }
        return (jpeg, "image.jpg", "image/jpeg")
    }
}

private struct SpecialChatMessageBubble: View {
    let message: RemoteSpecialChatMessage
    let maxBubbleWidth: CGFloat
    let maxMediaWidth: CGFloat
    let onPlayVideo: (URL) -> Void
    let onViewImage: (UIImage) -> Void
    private var outgoing: Bool { !message.isFromAdmin }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if outgoing { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 7) {
                if let mediaUrl = message.mediaUrl, let mediaType = message.mediaType {
                    SpecialChatMediaPreview(path: mediaUrl, mimeType: mediaType, maxWidth: maxMediaWidth, onPlayVideo: onPlayVideo, onViewImage: onViewImage)
                }
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .font(.auroraBody(12))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(message.createdAt.chatTimeLabel)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(outgoing ? Color.auroraViolet.opacity(0.29) : Color.auroraRaised.opacity(0.95), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(outgoing ? Color.auroraViolet.opacity(0.27) : Color.white.opacity(0.08), lineWidth: 0.8)
            }
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            if !outgoing { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
    }
}

private struct SpecialChatMediaPreview: View {
    let path: String
    let mimeType: String
    let maxWidth: CGFloat
    let onPlayVideo: (URL) -> Void
    let onViewImage: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error = false
    @State private var errorMessage: String?
    @State private var retryToken = 0

    private var isVideo: Bool { mimeType.lowercased().hasPrefix("video/") }
    private var imageDisplaySize: CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: min(maxWidth, 220), height: 160)
        }
        let factor = min(1, min(maxWidth / image.size.width, 280 / image.size.height))
        return CGSize(width: max(1, image.size.width * factor), height: max(1, image.size.height * factor))
    }

    var body: some View {
        Group {
            if isVideo {
                Button { Task { await loadVideo() } } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.auroraRaised, .auroraInk], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                        if isLoading { ProgressView().tint(.white) }
                        else {
                            Image(systemName: error ? "exclamationmark.triangle.fill" : "play.circle.fill")
                                .font(.system(size: 42, weight: .regular))
                                .foregroundStyle(error ? Color.auroraAmber : Color.auroraAccent)
                            VStack {
                                Spacer()
                                Text(error ? (errorMessage ?? "Không tải được video · chạm để thử lại") : "Video · chạm để mở trình phát")
                                    .font(.auroraLabel(9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: maxWidth)
            } else if let image {
                Button { onViewImage(image) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageDisplaySize.width, height: imageDisplaySize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.62), in: Circle())
                            .padding(8)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mở ảnh đính kèm toàn màn hình")
            } else {
                Button {
                    guard error, !isLoading else { return }
                    error = false
                    errorMessage = nil
                    retryToken += 1
                } label: {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().tint(.auroraSky) }
                        else { Image(systemName: error ? "arrow.clockwise.circle" : "photo.fill").foregroundStyle(Color.auroraSky) }
                        Text(error ? (errorMessage ?? "Không tải được ảnh · chạm để thử lại") : "Đang tải ảnh…")
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                    .frame(maxWidth: maxWidth, minHeight: 64)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!error || isLoading)
            }
        }
        .task(id: "\(path)-\(retryToken)") {
            guard !isVideo, image == nil else { return }
            isLoading = true
            error = false
            errorMessage = nil
            do {
                let data = try await CinemaAPI.shared.specialChatMediaData(path: path)
                image = UIImage(data: data)
                error = image == nil
                if error { errorMessage = "Dữ liệu ảnh không hợp lệ · chạm để thử lại" }
            } catch {
                self.error = true
                errorMessage = "Không tải được ảnh · chạm để thử lại"
            }
            isLoading = false
        }
    }

    @MainActor
    private func loadVideo() async {
        guard !isLoading else { return }
        guard mimeType.lowercased() != "video/webm" else {
            error = true
            errorMessage = "Video WebM chưa phát được trên app iOS. Hãy dùng MP4 hoặc MOV."
            return
        }
        isLoading = true
        error = false
        errorMessage = nil
        do {
            let data = try await CinemaAPI.shared.specialChatMediaData(path: path)
            let ext: String
            switch mimeType.lowercased() {
            case "video/quicktime": ext = "mov"
            case "video/webm": ext = "webm"
            default: ext = "mp4"
            }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cinemora-chat-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try data.write(to: fileURL, options: .atomic)
            onPlayVideo(fileURL)
        } catch {
            self.error = true
            errorMessage = "Không tải được video · chạm để thử lại"
        }
        isLoading = false
    }
}

private struct SpecialChatMediaViewerItem: Identifiable {
    enum Content {
        case image(UIImage)
        case video(URL)
    }
    let id = UUID()
    let content: Content
}

private struct PendingSpecialChatMedia {
    let attachmentId: Int
    let userID: Int
    let text: String?
    let clientRequestID: String
}

private struct SpecialChatImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom)
                .gesture(MagnificationGesture().onChanged { value in
                    zoom = min(4, max(1, value))
                }.onEnded { _ in
                    if zoom < 1.05 { withAnimation(.easeOut(duration: 0.18)) { zoom = 1 } }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Ảnh đính kèm, chụm hoặc tách hai ngón để phóng to")
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    Spacer()
                    Text("Ảnh trong tin nhắn")
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "xmark").font(.system(size: 14)).frame(width: 40, height: 40).hidden()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                Spacer()
                Text("Chụm hoặc tách hai ngón để thu phóng")
                    .font(.auroraBody(9))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.bottom, 14)
            }
        }
        .statusBarHidden()
    }
}

private struct SpecialChatVideoPlayerSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var isPlaying = true
    @State private var isSeeking = false
    @State private var isMuted = false
    @State private var timeObserver: Any?
    @State private var playbackError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    Spacer()
                    Text("Video trong tin nhắn")
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { isMuted.toggle(); player?.isMuted = isMuted } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(isMuted ? "Bật âm thanh" : "Tắt âm thanh")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer(minLength: 18)
                if let player {
                    SpecialChatPlayerSurface(player: player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                } else {
                    ProgressView().tint(Color.auroraAccent).frame(maxWidth: .infinity).aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
                Spacer(minLength: 22)

                if let playbackError {
                    Text(playbackError)
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraPink)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                Slider(value: $currentTime, in: 0...max(duration, 1), onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { seek(to: currentTime) }
                })
                .tint(Color.auroraAccent)
                .disabled(duration <= 0 || playbackError != nil)
                HStack {
                    Text(Self.timeLabel(currentTime))
                    Spacer()
                    Text(Self.timeLabel(duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.top, 1)

                HStack(spacing: 34) {
                    Button { seek(by: -10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Tua lùi 10 giây")
                    Button { togglePlayback() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.auroraVoid)
                            .frame(width: 58, height: 58)
                            .background(LinearGradient.auroraPrimary, in: Circle())
                    }
                    .accessibilityLabel(isPlaying ? "Tạm dừng video" : "Phát video")
                    Button { seek(by: 10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Tua tới 10 giây")
                }
                .padding(.top, 22)
                .padding(.bottom, 22)
            }
            .padding(.horizontal, 14)
        }
        .statusBarHidden()
        .onAppear(perform: startPlayback)
        .task {
            do {
                let asset = AVURLAsset(url: fileURL)
                let durationTime = try await asset.load(.duration)
                let loadedDuration = durationTime.seconds
                if loadedDuration.isFinite && loadedDuration > 0 { duration = loadedDuration }
            } catch {
                playbackError = "Không đọc được thời lượng video này."
            }
        }
        .onDisappear(perform: stopPlayback)
    }

    private func startPlayback() {
        let newPlayer = AVPlayer(url: fileURL)
        player = newPlayer
        newPlayer.play()
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            if !isSeeking, time.seconds.isFinite, time.seconds >= 0 { currentTime = time.seconds }
            let itemDuration = newPlayer.currentItem?.duration.seconds ?? 0
            if itemDuration.isFinite && itemDuration > 0 { duration = itemDuration }
            isPlaying = newPlayer.timeControlStatus == .playing
        }
    }

    private func stopPlayback() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.25 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(by offset: Double) {
        let base = player?.currentTime().seconds ?? currentTime
        guard base.isFinite else { return }
        seek(to: base + offset)
    }

    private func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let upperBound = duration > 0 ? duration : max(0, seconds)
        let bounded = min(max(0, seconds), upperBound)
        currentTime = bounded
        player?.seek(
            to: CMTime(seconds: bounded, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct SpecialChatPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> SpecialChatPlayerView {
        let view = SpecialChatPlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: SpecialChatPlayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

private final class SpecialChatPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private enum SpecialChatOperation {
    case text
    case media

    var fallbackMessage: String {
        switch self {
        case .text: return "Không thể gửi tin nhắn lúc này. Vui lòng thử lại sau."
        case .media: return "Không thể tải tệp lên lúc này. Vui lòng thử lại sau."
        }
    }
}

private func friendlySpecialChatError(_ error: Error, operation: SpecialChatOperation) -> String {
    if let knownError = error as? SpecialChatClientError {
        return knownError.localizedDescription
    }

    if let apiError = error as? APIError {
        switch apiError {
        case .rateLimited(let seconds):
            return "Bạn thao tác quá nhanh. Vui lòng thử lại sau khoảng \(max(1, seconds)) giây."
        case .http(let status) where status == 401 || status == 403:
            return "Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại rồi thử lại."
        case .invalidURL, .invalidResponse, .decoding(_), .server(_), .http(_):
            return operation.fallbackMessage
        }
    }

    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return "Kết nối không ổn định. Vui lòng kiểm tra mạng rồi thử lại."
        default:
            break
        }
    }

    return operation.fallbackMessage
}

private enum SpecialChatClientError: LocalizedError {
    case invalidFile
    case unsupportedVideo
    case imageTooLarge
    case videoTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Không đọc được tệp đã chọn."
        case .unsupportedVideo: return "Trên app iOS, video cần ở định dạng MP4 hoặc MOV."
        case .imageTooLarge: return "Ảnh vượt quá giới hạn 8 MB."
        case .videoTooLarge: return "Video vượt quá giới hạn 32 MB."
        }
    }
}

private extension String {
    var chatTimeLabel: String {
        let iso = ISO8601DateFormatter()
        let date = iso.date(from: self) ?? ISO8601DateFormatter.withFractionalSeconds.date(from: self)
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

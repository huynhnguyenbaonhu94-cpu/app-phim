import AVFoundation
import AVKit
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
    @State private var isPhotoPickerPresented = false
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
                if errorNote != nil || pendingMedia != nil || isUploading {
                    VStack(alignment: .leading, spacing: 7) {
                        if isUploading {
                            HStack(spacing: 8) {
                                ProgressView().tint(Color.auroraSky)
                                Text("Đang xử lý và gửi tệp đính kèm…")
                                    .font(.auroraBody(10))
                                    .foregroundStyle(Color.auroraTextSecondary)
                            }
                        }
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
        .fullScreenCover(isPresented: $isPhotoPickerPresented) {
            SpecialChatLibraryPicker { item, pickerError in
                isPhotoPickerPresented = false
                if let pickerError {
                    errorNote = pickerError
                    actionErrorVisible = true
                    return
                }
                guard let item else { return }
                Task { await sendPickedMedia(item) }
            }
            .ignoresSafeArea()
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
                            let rowWidth = max(1, geometry.size.width - 28)
                            let bubbleWidth = min(420, rowWidth * 0.82)
                            SpecialChatMessageBubble(
                                message: message,
                                userID: store.accountUser?.id ?? 0,
                                rowWidth: rowWidth,
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
                    // A vertical ScrollView does not always propose its viewport width
                    // to LazyVStack. Give the stack an explicit width so each HStack
                    // row has real trailing space for member messages to align right.
                    .frame(width: max(1, geometry.size.width - 28), alignment: .leading)
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
            Button {
                isPhotoPickerPresented = true
            } label: {
                Image(systemName: isUploading ? "hourglass" : "paperclip")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isUploading ? Color.auroraTextTertiary : Color.auroraSky)
                    .frame(width: 42, height: 42)
                    .background(Color.auroraSky.opacity(0.10), in: Circle())
                    .overlay(Circle().strokeBorder(Color.auroraSky.opacity(0.20), lineWidth: 0.8))
            }
            .disabled(isSending || isUploading || pendingMedia != nil || store.accountUser?.hasSpecialPrivileges != true)
            .buttonStyle(.plain)
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
    private func sendPickedMedia(_ item: SpecialChatPickedItem) async {
        guard !isUploading, pendingMedia == nil, let ownerUserID = store.accountUser?.id, store.accountUser?.hasSpecialPrivileges == true else { return }
        isUploading = true
        actionErrorVisible = false
        errorNote = nil
        defer {
            isUploading = false
        }
        do {
            let prepared = try await loadPickedMedia(item)
            let uploaded = try await api.uploadSpecialChatMedia(data: prepared.data, filename: prepared.filename, mimeType: prepared.mimeType, mediaWidth: prepared.mediaWidth, mediaHeight: prepared.mediaHeight)
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

    private func prepareMedia(_ data: Data, contentType: UTType?, mediaWidth: Int? = nil, mediaHeight: Int? = nil) throws -> (data: Data, filename: String, mimeType: String, mediaWidth: Int?, mediaHeight: Int?) {
        if contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .video) == true {
            let mime = contentType?.preferredMIMEType ?? "video/mp4"
            guard ["video/mp4", "video/quicktime"].contains(mime) else { throw SpecialChatClientError.unsupportedVideo }
            guard data.count <= 32 * 1024 * 1024 else { throw SpecialChatClientError.videoTooLarge }
            let ext = contentType?.preferredFilenameExtension ?? (mime == "video/quicktime" ? "mov" : "mp4")
            return (data, "video.\(ext)", mime, mediaWidth, mediaHeight)
        }

        if contentType?.preferredMIMEType == "image/gif" {
            guard data.count <= 8 * 1024 * 1024 else { throw SpecialChatClientError.imageTooLarge }
            let image = UIImage(data: data)
            return (data, "image.gif", "image/gif", image.map { Int($0.size.width.rounded()) }, image.map { Int($0.size.height.rounded()) })
        }
        guard let image = UIImage(data: data) else { throw SpecialChatClientError.invalidFile }
        let maxDimension: CGFloat = 1800
        let factor = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * factor), height: max(1, image.size.height * factor))
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.82) else { throw SpecialChatClientError.invalidFile }
        guard jpeg.count <= 8 * 1024 * 1024 else { throw SpecialChatClientError.imageTooLarge }
        return (jpeg, "image.jpg", "image/jpeg", Int(size.width.rounded()), Int(size.height.rounded()))
    }

    private func loadPickedMedia(_ item: SpecialChatPickedItem) async throws -> (data: Data, filename: String, mimeType: String, mediaWidth: Int?, mediaHeight: Int?) {
        let data: Data
        var mediaWidth: Int?
        var mediaHeight: Int?
        if let pickedData = item.data {
            data = pickedData
        } else if let temporaryURL = item.localURL {
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let isVideo = item.contentType.conforms(to: .movie) || item.contentType.conforms(to: .video)
            if isVideo && byteCount > 32 * 1024 * 1024 { throw SpecialChatClientError.videoTooLarge }
            if isVideo {
                (mediaWidth, mediaHeight) = await videoDisplayDimensions(at: temporaryURL)
            }
            data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        } else {
            throw SpecialChatClientError.invalidFile
        }
        guard !data.isEmpty else { throw SpecialChatClientError.invalidFile }
        return try prepareMedia(data, contentType: item.contentType, mediaWidth: mediaWidth, mediaHeight: mediaHeight)
    }

    private func videoDisplayDimensions(at url: URL) async -> (Int?, Int?) {
        do {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return (nil, nil) }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let displayedSize = naturalSize.applying(transform)
            let width = abs(displayedSize.width)
            let height = abs(displayedSize.height)
            guard width.isFinite, height.isFinite, width >= 1, height >= 1, width <= 16384, height <= 16384 else { return (nil, nil) }
            return (Int(width.rounded()), Int(height.rounded()))
        } catch {
            return (nil, nil)
        }
    }
}

private struct SpecialChatMessageBubble: View {
    let message: RemoteSpecialChatMessage
    let userID: Int
    let rowWidth: CGFloat
    let maxBubbleWidth: CGFloat
    let maxMediaWidth: CGFloat
    let onPlayVideo: (URL) -> Void
    let onViewImage: (UIImage) -> Void
    private var outgoing: Bool { !message.isFromAdmin }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(message.isFromAdmin ? "QUẢN TRỊ VIÊN" : "BẠN")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(outgoing ? Color.auroraAmber : Color.auroraMint)
            if let mediaUrl = message.mediaUrl, let mediaType = message.mediaType {
                SpecialChatMediaPreview(path: mediaUrl, mimeType: mediaType, userID: userID, mediaWidth: message.mediaWidth, mediaHeight: message.mediaHeight, maxWidth: maxMediaWidth, onPlayVideo: onPlayVideo, onViewImage: onViewImage)
            }
            if let text = message.text, !text.isEmpty {
                Text(text)
                    .font(.auroraBody(13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message.createdAt.chatTimeLabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.50))
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(outgoing ? Color.auroraViolet.opacity(0.29) : Color.auroraRaised.opacity(0.95), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(outgoing ? Color.auroraViolet.opacity(0.34) : Color.white.opacity(0.10), lineWidth: 0.8)
        }
        // First constrain the bubble itself; then place that bubble in an exact-width
        // row. This does not depend on Spacer expansion inside a lazy scroll stack.
        .frame(maxWidth: maxBubbleWidth, alignment: outgoing ? .trailing : .leading)
        .frame(width: rowWidth, alignment: outgoing ? .trailing : .leading)
    }
}

private struct SpecialChatMediaPreview: View {
    let path: String
    let mimeType: String
    let userID: Int
    let mediaWidth: Double?
    let mediaHeight: Double?
    let maxWidth: CGFloat
    let onPlayVideo: (URL) -> Void
    let onViewImage: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error = false
    @State private var errorMessage: String?
    @State private var retryToken = 0
    @State private var discoveredVideoAspectRatio: CGFloat?

    private var isVideo: Bool { mimeType.lowercased().hasPrefix("video/") }
    private var cacheKey: String { "\(userID):\(path)" }
    private var mediaAspectRatio: CGFloat? {
        if let width = mediaWidth, let height = mediaHeight, width > 0, height > 0 {
            return CGFloat(width / height)
        }
        return discoveredVideoAspectRatio ?? SpecialChatMediaCache.shared.aspectRatio(for: cacheKey)
    }
    private var videoDisplaySize: CGSize {
        let ratio = mediaAspectRatio ?? (16.0 / 9.0)
        let width = min(max(1, maxWidth), 320 * ratio)
        return CGSize(width: width, height: width / ratio)
    }
    private var imageDisplaySize: CGSize {
        guard let image = image ?? SpecialChatMediaCache.shared.image(for: cacheKey), image.size.width > 0, image.size.height > 0 else {
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
                            .overlay(alignment: .topLeading) {
                                Label("VIDEO", systemImage: "video.fill")
                                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.74))
                                    .padding(10)
                            }
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
                    .frame(width: videoDisplaySize.width, height: videoDisplaySize.height)
                }
                .buttonStyle(.plain)
                .frame(width: videoDisplaySize.width, height: videoDisplaySize.height)
            } else if let image = image ?? SpecialChatMediaCache.shared.image(for: cacheKey) {
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
            guard !isVideo else { return }
            if let cached = SpecialChatMediaCache.shared.image(for: cacheKey) {
                image = cached
                isLoading = false
                return
            }
            guard image == nil else { return }
            isLoading = true
            error = false
            errorMessage = nil
            do {
                let data = try await CinemaAPI.shared.specialChatMediaData(path: path)
                image = UIImage(data: data)
                if let image { SpecialChatMediaCache.shared.insert(image, for: cacheKey) }
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
            let data: Data
            if let cached = SpecialChatMediaCache.shared.videoData(for: cacheKey) {
                data = cached
            } else {
                data = try await CinemaAPI.shared.specialChatMediaData(path: path)
                SpecialChatMediaCache.shared.insertVideoData(data, for: cacheKey)
            }
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
            if mediaWidth == nil || mediaHeight == nil,
               let measuredRatio = await Self.videoAspectRatio(at: fileURL) {
                discoveredVideoAspectRatio = measuredRatio
                SpecialChatMediaCache.shared.insertAspectRatio(measuredRatio, for: cacheKey)
            }
            onPlayVideo(fileURL)
        } catch {
            self.error = true
            errorMessage = "Không tải được video · chạm để thử lại"
        }
        isLoading = false
    }

    private static func videoAspectRatio(at url: URL) async -> CGFloat? {
        do {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let displayedSize = naturalSize.applying(transform)
            let width = abs(displayedSize.width)
            let height = abs(displayedSize.height)
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            return width / height
        } catch {
            return nil
        }
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
    @State private var playerLooper: AVPlayerLooper?
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var isPlaying = true
    @State private var isSeeking = false
    @State private var isMuted = false
    @State private var timeObserver: Any?
    @State private var playbackError: String?
    @State private var videoAspectRatio: CGFloat = 9.0 / 16.0

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
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                } else {
                    ProgressView().tint(Color.auroraAccent).frame(maxWidth: .infinity).aspectRatio(videoAspectRatio, contentMode: .fit)
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
            let asset = AVURLAsset(url: fileURL)
            do {
                let durationTime = try await asset.load(.duration)
                let loadedDuration = durationTime.seconds
                if loadedDuration.isFinite && loadedDuration > 0 { duration = loadedDuration }
            } catch {
                playbackError = "Không đọc được thời lượng video này."
            }
            // Use the encoded orientation so phone-shot portrait clips fill the
            // available screen height instead of being letterboxed in a 16:9 frame.
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let naturalSize = try await track.load(.naturalSize)
                    let preferredTransform = try await track.load(.preferredTransform)
                    let displayedSize = naturalSize.applying(preferredTransform)
                    let width = abs(displayedSize.width)
                    let height = abs(displayedSize.height)
                    if width > 0, height > 0 {
                        videoAspectRatio = width / height
                    }
                }
            } catch {
                // Keep a portrait-friendly fallback; playback does not depend on metadata.
            }
        }
        .onDisappear(perform: stopPlayback)
    }

    private func startPlayback() {
        let item = AVPlayerItem(url: fileURL)
        let queuePlayer = AVQueuePlayer()
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer
        queuePlayer.play()
        timeObserver = queuePlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            if !isSeeking, time.seconds.isFinite, time.seconds >= 0 { currentTime = time.seconds }
            let itemDuration = queuePlayer.currentItem?.duration.seconds ?? 0
            if itemDuration.isFinite && itemDuration > 0 { duration = itemDuration }
            isPlaying = queuePlayer.timeControlStatus == .playing
        }
    }

    private func stopPlayback() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playerLooper = nil
        player = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
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
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .positiveInfinity
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

private struct SpecialChatPickedItem {
    let contentType: UTType
    let localURL: URL?
    let data: Data?
}

private struct SpecialChatLibraryPicker: UIViewControllerRepresentable {
    let onPick: (SpecialChatPickedItem?, String?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: SpecialChatLibraryPicker

        init(parent: SpecialChatLibraryPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onPick(nil, nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let mediaIdentifier = info[.mediaType] as? String,
                  let mediaType = UTType(mediaIdentifier) else {
                parent.onPick(nil, "Không xác định được định dạng tệp đã chọn.")
                return
            }
            if mediaType.conforms(to: .movie) || mediaType.conforms(to: .video) {
                guard let source = info[.mediaURL] as? URL else {
                    parent.onPick(nil, "Không đọc được tệp video đã chọn.")
                    return
                }
                do {
                    let localURL = try copyToTemporaryDirectory(source, fallbackType: mediaType)
                    let contentType = UTType(filenameExtension: localURL.pathExtension) ?? mediaType
                    parent.onPick(SpecialChatPickedItem(contentType: contentType, localURL: localURL, data: nil), nil)
                } catch {
                    parent.onPick(nil, "Không thể chuẩn bị video đã chọn. Hãy thử chọn lại.")
                }
                return
            }
            if let source = info[.imageURL] as? URL, let localURL = try? copyToTemporaryDirectory(source, fallbackType: mediaType) {
                let contentType = UTType(filenameExtension: localURL.pathExtension) ?? mediaType
                parent.onPick(SpecialChatPickedItem(contentType: contentType, localURL: localURL, data: nil), nil)
                return
            }
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.92) {
                parent.onPick(SpecialChatPickedItem(contentType: .jpeg, localURL: nil, data: data), nil)
                return
            }
            parent.onPick(nil, "Không đọc được ảnh đã chọn. Hãy thử chọn lại.")
        }

        private func copyToTemporaryDirectory(_ source: URL, fallbackType: UTType) throws -> URL {
            let ext = source.pathExtension.isEmpty ? (fallbackType.preferredFilenameExtension ?? "bin") : source.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("cinemora-chat-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
    }
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
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        let date = iso.date(from: self) ?? ISO8601DateFormatter.withFractionalSeconds.date(from: self)
            ?? Self.utcNaiveDateFormatter.date(from: self)
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static let utcNaiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }()
}

private final class SpecialChatMediaCache {
    static let shared = SpecialChatMediaCache()
    private let images = NSCache<NSString, UIImage>()
    private let videos = NSCache<NSString, NSData>()
    private let aspectRatios = NSCache<NSString, NSNumber>()

    private init() {
        images.totalCostLimit = 48 * 1024 * 1024
        videos.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? { images.object(forKey: key as NSString) }
    func insert(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
        images.setObject(image, forKey: key as NSString, cost: max(1, cost))
    }
    func videoData(for key: String) -> Data? { videos.object(forKey: key as NSString) as Data? }
    func insertVideoData(_ data: Data, for key: String) {
        guard data.count <= videos.totalCostLimit else { return }
        videos.setObject(data as NSData, forKey: key as NSString, cost: data.count)
    }
    func aspectRatio(for key: String) -> CGFloat? {
        guard let value = aspectRatios.object(forKey: key as NSString)?.doubleValue, value.isFinite, value > 0 else { return nil }
        return CGFloat(value)
    }
    func insertAspectRatio(_ ratio: CGFloat, for key: String) {
        guard ratio.isFinite, ratio > 0 else { return }
        aspectRatios.setObject(NSNumber(value: Double(ratio)), forKey: key as NSString)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

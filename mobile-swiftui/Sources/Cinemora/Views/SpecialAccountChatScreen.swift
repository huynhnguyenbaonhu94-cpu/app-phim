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
    @State private var selectedMedia: PhotosPickerItem?
    @State private var isLoading = true
    @State private var isSending = false
    @State private var isUploading = false
    @State private var errorNote: String?
    @State private var videoPlayback: SpecialChatVideoPlayback?
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
                if let errorNote {
                    Text(errorNote)
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraPink)
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
                isLoading = false
                errorNote = "Tài khoản chưa được cấp quyền sử dụng chat đặc biệt."
                return
            }
            if loadedUserID != account.id {
                messages = []
                loadedUserID = account.id
                isLoading = true
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
        .sheet(item: $videoPlayback) { playback in
            NavigationStack {
                SpecialChatVideoPlayerSheet(fileURL: playback.fileURL)
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
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        SpecialChatMessageBubble(message: message) { fileURL in
                            videoPlayback = SpecialChatVideoPlayback(fileURL: fileURL)
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
            .disabled(isSending || isUploading || store.accountUser?.hasSpecialPrivileges != true)
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
                .disabled(isUploading)

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
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && store.accountUser?.hasSpecialPrivileges == true
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
            errorNote = nil
            isLoading = false
        } catch {
            isLoading = false
            errorNote = messages.isEmpty ? "Không tải được tin nhắn. Hãy thử lại khi mạng ổn định." : "Chưa đồng bộ được tin nhắn mới. Đang tiếp tục thử lại…"
        }
    }

    @MainActor
    private func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        errorNote = nil
        do {
            let message = try await api.sendSpecialChatMessage(text: text, attachmentId: nil)
            append(message)
            draft = ""
            composerFocused = true
        } catch {
            errorNote = error.localizedDescription
        }
        isSending = false
    }

    @MainActor
    private func sendPickedMedia(_ item: PhotosPickerItem) async {
        selectedMedia = nil
        guard !isUploading, store.accountUser?.hasSpecialPrivileges == true else { return }
        isUploading = true
        errorNote = nil
        defer { isUploading = false }
        do {
            guard let original = try await item.loadTransferable(type: Data.self), !original.isEmpty else {
                throw SpecialChatClientError.invalidFile
            }
            let contentType = item.supportedContentTypes.first
            let prepared = try prepareMedia(original, contentType: contentType)
            let uploaded = try await api.uploadSpecialChatMedia(data: prepared.data, filename: prepared.filename, mimeType: prepared.mimeType)
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = try await api.sendSpecialChatMessage(text: text.isEmpty ? nil : text, attachmentId: uploaded.attachmentId)
            append(message)
            draft = ""
        } catch {
            errorNote = error.localizedDescription
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
            guard ["video/mp4", "video/quicktime", "video/webm"].contains(mime) else { throw SpecialChatClientError.unsupportedVideo }
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
    let onPlayVideo: (URL) -> Void
    private var outgoing: Bool { !message.isFromAdmin }

    var body: some View {
        HStack {
            if outgoing { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 7) {
                if let mediaUrl = message.mediaUrl, let mediaType = message.mediaType {
                    SpecialChatMediaPreview(path: mediaUrl, mimeType: mediaType, onPlayVideo: onPlayVideo)
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
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(outgoing ? Color.auroraViolet.opacity(0.29) : Color.auroraRaised.opacity(0.95), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(outgoing ? Color.auroraViolet.opacity(0.27) : Color.white.opacity(0.08), lineWidth: 0.8)
            }
            if !outgoing { Spacer(minLength: 42) }
        }
    }
}

private struct SpecialChatMediaPreview: View {
    let path: String
    let mimeType: String
    let onPlayVideo: (URL) -> Void
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error = false

    private var isVideo: Bool { mimeType.lowercased().hasPrefix("video/") }

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
                                Text("Video · nhấn để phát")
                                    .font(.auroraLabel(9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Ảnh được gửi trong chat")
            } else {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.auroraSky) }
                    else { Image(systemName: error ? "photo.badge.exclamationmark" : "photo.fill").foregroundStyle(Color.auroraSky) }
                    Text(error ? "Không tải được ảnh đính kèm" : "Đang tải ảnh…")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                .frame(width: 210, height: 64)
            }
        }
        .task(id: path) {
            guard !isVideo, image == nil else { return }
            isLoading = true
            do {
                let data = try await CinemaAPI.shared.specialChatMediaData(path: path)
                image = UIImage(data: data)
                error = image == nil
            } catch { self.error = true }
            isLoading = false
        }
    }

    @MainActor
    private func loadVideo() async {
        guard !isLoading else { return }
        isLoading = true
        error = false
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
        } catch { self.error = true }
        isLoading = false
    }
}

private struct SpecialChatVideoPlayback: Identifiable {
    let fileURL: URL
    var id: URL { fileURL }
}

private struct SpecialChatVideoPlayerSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            else { ProgressView().tint(.white) }
        }
        .navigationTitle("Video trong tin nhắn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Đóng") { dismiss() }.foregroundStyle(Color.auroraAccent)
            }
        }
        .onAppear {
            let newPlayer = AVPlayer(url: fileURL)
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

private enum SpecialChatClientError: LocalizedError {
    case invalidFile
    case unsupportedVideo
    case imageTooLarge
    case videoTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Không đọc được tệp đã chọn."
        case .unsupportedVideo: return "Video phải ở định dạng MP4, MOV hoặc WebM."
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

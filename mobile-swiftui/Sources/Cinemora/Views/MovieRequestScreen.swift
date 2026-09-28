import PhotosUI
import SwiftUI
import UIKit

struct MovieRequestScreen: View {
    @State private var title = ""
    @State private var link = ""
    @State private var priority = "Bình thường"
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imagePreview: UIImage?
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var showSuccess = false

    private let priorities = ["Thấp", "Bình thường", "Cao", "Khẩn cấp"]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionEyebrow(text: "CINEMORA · ĐÓNG GÓP")
                        Text("Yêu cầu phim")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Gửi yêu cầu phim bạn muốn xem. Chúng tôi sẽ cố gắng cập nhật sớm nhất có thể!")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    requestField(title: "Tên phim", placeholder: "Tên phim, tên gốc, năm sản xuất, quốc gia…", text: $title)
                    requestField(title: "Link TMDB hoặc IMDB (nếu có)", placeholder: "https://www.imdb.com/title/…", text: $link)

                    VStack(alignment: .leading, spacing: 9) {
                        SectionEyebrow(text: "MỨC ĐỘ ƯU TIÊN")
                        Picker("Mức độ ưu tiên", selection: $priority) {
                            ForEach(priorities, id: \.self) { value in
                                Text(value).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.cinemaAccent)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        SectionEyebrow(text: "GHI CHÚ THÊM (NẾU CÓ)")
                        TextEditor(text: $notes)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 125)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        SectionEyebrow(text: "HÌNH ẢNH (NẾU CÓ)")
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            Label(imagePreview == nil ? "Chọn hình ảnh" : "Đổi hình ảnh", systemImage: "photo.on.rectangle.angled")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.cinemaInk)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 11)
                                .background(Color.cinemaAccent, in: Capsule())
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            guard let item else { return }
                            Task {
                                guard let data = try? await item.loadTransferable(type: Data.self),
                                      let image = UIImage(data: data),
                                      let compressed = Self.prepareImageData(image) else { return }
                                await MainActor.run {
                                    imagePreview = image
                                    imageData = compressed
                                }
                            }
                        }
                        if let preview = imagePreview {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.15), lineWidth: 0.7))
                                Button {
                                    selectedPhoto = nil
                                    imagePreview = nil
                                    imageData = nil
                                } label: {
                                    Label("Gỡ ảnh đã chọn", systemImage: "trash")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.red.opacity(0.9))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Xóa ảnh đã chọn")
                            }
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting { ProgressView().tint(Color.cinemaInk) }
                            Text(isSubmitting ? "Đang gửi…" : "Gửi yêu cầu phim")
                        }
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Color.cinemaInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cinemaAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ? 0.48 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 50)
            }
        }
        .navigationTitle("Yêu cầu phim")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Đã gửi yêu cầu", isPresented: $showSuccess) {
            Button("Đóng", role: .cancel) { }
        } message: {
            Text("Cảm ơn bạn. Yêu cầu phim đã được gửi đến đội ngũ Cinemora.")
        }
    }

    private func requestField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: title.uppercased())
            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1...3)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
        }
    }

    private static func prepareImageData(_ image: UIImage) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longestSide, 1))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        var quality: CGFloat = 0.68
        var data = renderer.jpegData(withCompressionQuality: quality) { image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        while data.count > 7 * 1024 * 1024 && quality > 0.28 {
            quality -= 0.08
            data = renderer.jpegData(withCompressionQuality: quality) { image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        }
        return data.count <= 7 * 1024 * 1024 ? data : nil
    }

    private func submit() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count >= 2, !isSubmitting else { return }
        isSubmitting = true
        message = nil
        Task {
            do {
                try await CinemaAPI.shared.submitMovieRequest(
                    title: cleanTitle,
                    link: link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : link.trimmingCharacters(in: .whitespacesAndNewlines),
                    priority: priority,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    imageData: imageData,
                    imageMimeType: imageData == nil ? nil : "image/jpeg"
                )
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                    title = ""
                    link = ""
                    notes = ""
                    imageData = nil
                    imagePreview = nil
                    selectedPhoto = nil
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    message = error.localizedDescription
                }
            }
        }
    }
}

import SwiftUI
import UIKit

/// Giải mã ảnh đại diện dạng data URL và nhớ lại kết quả.
///
/// Danh sách bình luận được dựng lại mỗi khi có bình luận mới, nên nếu giải mã lại
/// từng ảnh mỗi lần thì rất phí. `NSCache` tự giới hạn số lượng và đã an toàn khi
/// truy cập từ nhiều luồng.
enum AvatarImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        return cache
    }()

    static func image(for raw: String?) -> UIImage? {
        guard let raw, raw.count > 32 else { return nil }
        if let cached = cache.object(forKey: raw as NSString) { return cached }
        guard raw.hasPrefix("data:image/"), let comma = raw.firstIndex(of: ",") else { return nil }
        let encoded = String(raw[raw.index(after: comma)...])
        guard
            let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
            let image = UIImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: raw as NSString)
        return image
    }
}

/// Thu nhỏ ảnh người dùng chọn rồi đổi thành data URL để gửi lên máy chủ.
///
/// Ảnh được ép về tối đa 256 điểm ảnh và hạ chất lượng dần cho tới khi dưới 220 KB,
/// vừa đủ nét khi hiển thị tròn 34–56 pt mà không làm nặng dữ liệu bình luận.
enum AvatarUploader {
    static let maxDimension: CGFloat = 256
    private static let maxBytes = 220_000

    static func dataURL(from image: UIImage) -> String? {
        let side = max(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let scale = side > maxDimension ? maxDimension / side : 1
        let target = CGSize(
            width: max(32, (image.size.width * scale).rounded()),
            height: max(32, (image.size.height * scale).rounded())
        )
        let renderer = UIGraphicsImageRenderer(size: target)
        var quality: CGFloat = 0.72
        // jpegData trả về Data không tuỳ chọn, nhưng vòng lặp bên dưới cần bản
        // tuỳ chọn để hạ dần chất lượng, nên khai báo rõ kiểu ở đây.
        var data: Data? = renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        while let current = data, current.count > maxBytes, quality > 0.3 {
            quality -= 0.12
            data = renderer.jpegData(withCompressionQuality: quality) { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        guard let data, data.count <= 400_000 else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}

/// Vòng tròn ảnh đại diện dùng chung: có ảnh thì hiện ảnh, chưa có thì hiện chữ cái đầu.
struct AvatarCircle: View {
    let raw: String?
    let initials: String
    var size: CGFloat = 40
    var isAdmin: Bool = false

    var body: some View {
        ZStack {
            if let image = AvatarImageCache.image(for: raw) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(isAdmin
                        ? LinearGradient(colors: [Color(red: 0.29, green: 0.63, blue: 1.0), Color(red: 0.09, green: 0.40, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient.auroraPrimary)
                    .frame(width: size, height: size)
                Text(initials)
                    .font(.system(size: max(10, size * 0.4), weight: .black, design: .rounded))
                    .foregroundStyle(isAdmin ? .white : Color.auroraVoid)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
    }
}

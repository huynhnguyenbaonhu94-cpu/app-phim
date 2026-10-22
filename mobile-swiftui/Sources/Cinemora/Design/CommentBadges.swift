import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Bộ màu và hiệu ứng cho nhãn hiển thị (badge) và tên người dùng.
///
/// Nhãn do quản trị viên đặt trên website: chữ có màu, font, hiệu ứng, hoặc ảnh và GIF
/// nhỏ. Mọi chuyển động ở đây chỉ dùng `scaleEffect`, `opacity`, `offset` và gradient —
/// đều là hiệu ứng rẻ — và tự tắt khi bật *Reduce Motion* để danh sách bình luận dài
/// vẫn cuộn mượt.

extension Color {
    /// Đọc màu từ chuỗi hex mà trang quản trị gửi lên, ví dụ `#d2f36b`.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if value.count == 8 {
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        } else {
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// Kích thước hiển thị của nhãn ảnh/GIF trên app: cao 18pt, rộng tối đa 64pt.
enum CommentBadgeMetrics {
    static let imageHeight: CGFloat = 18
    static let imageMaxWidth: CGFloat = 64
    static let spacing: CGFloat = 5
}

// MARK: - Kho ảnh nhãn

/// Ảnh nhãn tải từ máy chủ, giữ trong bộ nhớ đệm nhỏ để cuộn danh sách không tải lại.
final class BadgeImageStore {
    struct Entry {
        let frames: [UIImage]
        let duration: Double

        var isAnimated: Bool { frames.count > 1 }

        /// Đọc ảnh tĩnh hoặc toàn bộ khung hình của GIF/WebP động.
        static func make(from data: Data) -> Entry {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return Entry(frames: [], duration: 0) }
            let count = max(1, CGImageSourceGetCount(source))
            var frames: [UIImage] = []
            var duration = 0.0
            for index in 0..<count {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) {
                    frames.append(UIImage(cgImage: cgImage))
                }
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                   let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                    let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                    let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
                    let delay = unclamped ?? clamped ?? 0.1
                    duration += delay > 0.02 ? delay : 0.1
                }
            }
            return Entry(frames: frames, duration: duration)
        }
    }

    static let shared = BadgeImageStore()

    private final class Box {
        let entry: Entry
        init(_ entry: Entry) { self.entry = entry }
    }

    private let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 60
        return cache
    }()

    private var tasks: [String: Task<Entry?, Never>] = [:]

    func cached(for key: String) -> Entry? {
        cache.object(forKey: key as NSString)?.entry
    }

    /// Tải ảnh một lần cho mỗi địa chỉ, nhiều hàng cùng lúc dùng chung một yêu cầu.
    func entry(for raw: String) async -> Entry? {
        if let cached = cached(for: raw) { return cached }
        if let running = tasks[raw] { return await running.value }
        let task = Task<Entry?, Never> { [cache] in
            guard let url = CinemaAPI.absoluteURL(raw) else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            let entry = Entry.make(from: data)
            guard !entry.frames.isEmpty else { return nil }
            cache.setObject(Box(entry), forKey: raw as NSString)
            return entry
        }
        tasks[raw] = task
        let entry = await task.value
        tasks[raw] = nil
        return entry
    }
}

/// Ảnh nhãn hiển thị trong danh sách bình luận, tự chạy khung hình nếu là GIF.
struct CommentBadgeImage: View {
    let urlString: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entry: BadgeImageStore.Entry?
    @State private var frameIndex = 0

    var body: some View {
        Group {
            if let entry, let first = entry.frames.first {
                if entry.isAnimated && !reduceMotion {
                    Image(uiImage: entry.frames[min(frameIndex, entry.frames.count - 1)])
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Color.clear
            }
        }
        .frame(height: CommentBadgeMetrics.imageHeight)
        .frame(maxWidth: CommentBadgeMetrics.imageMaxWidth, alignment: .leading)
        .task(id: urlString) {
            frameIndex = 0
            entry = await BadgeImageStore.shared.entry(for: urlString)
        }
        .task(id: entry?.frames.count ?? 0) {
            guard let entry, entry.isAnimated, !reduceMotion else { return }
            let step = max(0.06, entry.duration / Double(entry.frames.count))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                if Task.isCancelled { break }
                frameIndex = (frameIndex + 1) % entry.frames.count
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Nhãn

/// Một nhãn hiển thị: chữ có màu, font, hiệu ứng hoặc ảnh/GIF nhỏ.
struct CommentBadgeChip: View {
    let badge: CommentBadge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private var tint: Color { Color(hex: badge.color) ?? Color.auroraViolet }
    private var surface: Color { Color(hex: badge.background) ?? tint.opacity(0.18) }
    private var isOutline: Bool { badge.style == "outline" }
    private var isGlow: Bool { badge.style == "glow" || badge.animation == "float" }
    private var isGradient: Bool { badge.style == "gradient" }
    private var isShine: Bool { badge.style == "shine" || badge.animation == "shine" }
    private var isPulsing: Bool { badge.style == "pulse" || badge.animation == "pulse" }
    private var isFloating: Bool { badge.animation == "float" }

    private var fontSize: CGFloat {
        switch badge.size {
        case "sm": return 9
        case "lg": return 12
        default: return 10.5
        }
    }

    private var fontDesign: Font.Design {
        switch badge.font {
        case "serif": return .serif
        case "mono": return .monospaced
        case "script": return .serif
        default: return .rounded
        }
    }

    var body: some View {
        if badge.isImage {
            CommentBadgeImage(urlString: badge.imageURL)
        } else {
            Text(badge.text)
                .font(.system(size: fontSize, weight: .heavy, design: fontDesign).italic(badge.font == "script"))
                .foregroundStyle(isGradient ? AnyShapeStyle(LinearGradient(
                    colors: [tint, tint.opacity(0.55), tint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )) : AnyShapeStyle(tint))
                .lineLimit(1)
                .padding(.horizontal, badge.size == "lg" ? 9 : 7)
                .padding(.vertical, 2.5)
                .background {
                    if isOutline {
                        Capsule().fill(Color.clear)
                    } else if isGradient {
                        Capsule().fill(LinearGradient(
                            colors: [surface.opacity(0.95), surface.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    } else {
                        Capsule().fill(surface)
                    }
                }
                .overlay {
                    if isOutline {
                        Capsule().strokeBorder(tint.opacity(0.9), lineWidth: 1)
                    }
                }
                .overlay {
                    if isShine {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.clear, Color.white.opacity(animate ? 0.5 : 0.0), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .blendMode(.plusLighter)
                    }
                }
                .clipShape(Capsule())
                .shadow(color: isGlow ? tint.opacity(animate ? 0.55 : 0.3) : .clear, radius: 5)
                .scaleEffect(isPulsing && animate ? 1.06 : 1)
                .offset(y: isFloating && animate ? -1.5 : 0)
                .task(id: badge.id) { await runAnimation() }
        }
    }

    /// Nhịp chuyển động nhẹ, chỉ chạy khi nhãn thật sự có hiệu ứng.
    private func runAnimation() async {
        guard (isShine || isPulsing || isGlow || isFloating), !reduceMotion else { return }
        let duration = isShine ? 1.6 : 1.9
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: duration)) { animate.toggle() }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }
}

/// Dãy nhãn hiện cạnh tên người bình luận.
struct CommentBadgeRow: View {
    let badges: [CommentBadge]

    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: CommentBadgeMetrics.spacing) {
                ForEach(badges) { badge in
                    CommentBadgeChip(badge: badge)
                }
            }
        }
    }
}

// MARK: - Tên người dùng

/// Tên người dùng có màu và hiệu ứng làm nổi bật do quản trị viên đặt.
struct StyledCommentName: View {
    let name: String
    let style: CommentNameStyle?
    /// Quản trị viên luôn có kiểu mặc định nổi bật khi chưa đặt kiểu riêng.
    let isAdmin: Bool
    let isMine: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    private static let adminColors = [
        Color(red: 0.44, green: 0.72, blue: 1.0),
        Color(red: 0.16, green: 0.48, blue: 1.0),
    ]

    private var customColor: Color? { style?.color.isEmpty == false ? Color(hex: style?.color ?? "") : nil }
    private var effect: String { style?.effect ?? "none" }

    private var baseColor: Color {
        if let customColor { return customColor }
        if isAdmin { return Self.adminColors[0] }
        if isMine { return Color.auroraViolet }
        return Color.white.opacity(0.92)
    }

    var body: some View {
        Text(name)
            .font(.auroraLabel(12, weight: (isAdmin || effect != "none") ? .heavy : .bold))
            .lineLimit(1)
            .foregroundStyle(textStyle)
            .shadow(color: glowColor, radius: effect == "glow" || isAdmin ? 6 : 0)
            .opacity(effect == "shine" && phase ? 0.88 : 1)
            .task(id: effect) { await runEffect() }
    }

    private var textStyle: AnyShapeStyle {
        switch effect {
        case "gradient":
            return AnyShapeStyle(LinearGradient(colors: [baseColor, Color.white.opacity(0.92)], startPoint: .leading, endPoint: .trailing))
        case "shine":
            return AnyShapeStyle(LinearGradient(colors: [baseColor, Color.white, baseColor], startPoint: .leading, endPoint: .trailing))
        case "rainbow":
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.42, blue: 0.42),
                    Color(red: 1.0, green: 0.82, blue: 0.40),
                    Color(red: 0.49, green: 0.90, blue: 0.53),
                    Color(red: 0.39, green: 0.70, blue: 1.0),
                    Color(red: 0.78, green: 0.57, blue: 0.92),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        case "outline":
            return AnyShapeStyle(baseColor.opacity(0.98))
        default:
            if isAdmin && customColor == nil {
                return AnyShapeStyle(LinearGradient(colors: Self.adminColors, startPoint: .leading, endPoint: .trailing))
            }
            return AnyShapeStyle(baseColor)
        }
    }

    private var glowColor: Color {
        switch effect {
        case "glow": return baseColor.opacity(0.7)
        case "rainbow": return Color.white.opacity(phase ? 0.4 : 0.15)
        default: return isAdmin ? Self.adminColors[1].opacity(0.55) : .clear
        }
    }

    private func runEffect() async {
        guard !reduceMotion, effect == "shine" || effect == "rainbow" else { return }
        let duration = effect == "shine" ? 1.5 : 2.6
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: duration)) { phase.toggle() }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }
}
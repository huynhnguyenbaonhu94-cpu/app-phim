import SwiftUI
import UIKit

struct SubtitlePreferences: Codable, Equatable {
    var enabled = true
    var fontName = "System"
    var bold = false
    var fontSize: Double = 18
    var bottomSpacing: Double = 72
    var alignment = "Giữa"
    var textColorHex = "#FFFFFF"
    var outlineColorHex = "#000000"
    var outlineWidth: Double = 2
    var backgroundEnabled = false
    var backgroundColorHex = "#000000"
    var backgroundOpacity: Double = 0.65
    var bilingual = false

    static let `default` = SubtitlePreferences()
    var textColor: Color { Color(hex: textColorHex) }
    var outlineColor: Color { Color(hex: outlineColorHex) }
    var backgroundColor: Color { Color(hex: backgroundColorHex) }
    var safeBackgroundOpacity: Double { min(max(backgroundOpacity.isFinite ? backgroundOpacity : 0.65, 0.1), 1) }
    var textAlignment: TextAlignment {
        switch alignment { case "Trái": return .leading; case "Phải": return .trailing; default: return .center }
    }
    var frameAlignment: Alignment {
        switch alignment { case "Trái": return .leading; case "Phải": return .trailing; default: return .center }
    }
    var font: Font {
        let weight: Font.Weight = bold ? .bold : .regular
        return fontName == "System" ? .system(size: fontSize, weight: weight, design: .rounded) : .custom(fontName, size: fontSize).weight(weight)
    }
    private enum CodingKeys: String, CodingKey {
        case enabled, fontName, bold, fontSize, bottomSpacing, alignment
        case textColorHex, outlineColorHex, outlineWidth
        case backgroundEnabled, backgroundColorHex, backgroundOpacity, bilingual
    }
    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "System"
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 18
        bottomSpacing = try container.decodeIfPresent(Double.self, forKey: .bottomSpacing) ?? 72
        alignment = try container.decodeIfPresent(String.self, forKey: .alignment) ?? "Giữa"
        textColorHex = try container.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#FFFFFF"
        outlineColorHex = try container.decodeIfPresent(String.self, forKey: .outlineColorHex) ?? "#000000"
        outlineWidth = try container.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 2
        backgroundEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#000000"
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.65
        bilingual = try container.decodeIfPresent(Bool.self, forKey: .bilingual) ?? false
    }
    mutating func reset() { self = .default }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let normalized = cleaned.count == 6 ? cleaned : "000000"
        let value = UInt64(normalized, radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
    var hexString: String {
        #if os(iOS)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#FFFFFF"
        #endif
    }
}

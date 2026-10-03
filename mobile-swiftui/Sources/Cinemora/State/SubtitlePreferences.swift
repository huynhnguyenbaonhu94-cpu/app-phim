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
    var bilingual = false

    static let `default` = SubtitlePreferences()
    var textColor: Color { Color(hex: textColorHex) }
    var outlineColor: Color { Color(hex: outlineColorHex) }
    var textAlignment: TextAlignment {
        switch alignment { case "Trái": return .leading; case "Phải": return .trailing; default: return .center }
    }
    var font: Font {
        let weight: Font.Weight = bold ? .bold : .regular
        return fontName == "System" ? .system(size: fontSize, weight: weight, design: .rounded) : .custom(fontName, size: fontSize).weight(weight)
    }
    mutating func reset() { self = .default }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
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

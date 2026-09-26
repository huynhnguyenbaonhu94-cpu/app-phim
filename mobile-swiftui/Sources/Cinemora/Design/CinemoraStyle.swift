import SwiftUI

extension Color {
    static let cinemaInk = Color(red: 7.0 / 255.0, green: 9.0 / 255.0, blue: 15.0 / 255.0)
    static let cinemaAccent = Color(red: 197 / 255, green: 210 / 255, blue: 1)
    static let cinemaLavender = Color(red: 0.57, green: 0.64, blue: 0.98)
}

struct CinemaBackground: View {
    var body: some View {
        ZStack {
            Color.cinemaInk.ignoresSafeArea()
            GeometryReader { proxy in
                Circle().fill(Color.cinemaLavender.opacity(0.12)).frame(width: 320, height: 320).blur(radius: 100).offset(x: proxy.size.width * 0.48, y: -110)
                Circle().fill(Color.cinemaAccent.opacity(0.07)).frame(width: 260, height: 260).blur(radius: 90).offset(x: -130, y: proxy.size.height * 0.52)
            }.ignoresSafeArea()
        }
    }
}

struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color

    func body(content: Content) -> some View {
        content.background(.ultraThinMaterial, in: shape)
            .background(tint.opacity(0.5), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.8))
    }
}

extension View {
    func cinemaGlass<S: Shape>(in shape: S, tint: Color = .white.opacity(0.08)) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint))
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).tracking(2).foregroundStyle(Color.cinemaAccent)
    }
}

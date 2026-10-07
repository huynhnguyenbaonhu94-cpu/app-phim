import SwiftUI

// MARK: - Palette
//
// "Aurora" replaces the previous ice-blue Liquid Glass palette with a softer,
// warmer cinematic gradient family. Legacy names (cinemaInk / cinemaAccent /
// cinemaLavender) are kept as aliases so the whole app shares one source of
// truth instead of drifting into per-screen colours.

extension Color {
    static let auroraVoid = Color(red: 6 / 255, green: 5 / 255, blue: 17 / 255)
    static let auroraInk = Color(red: 12 / 255, green: 10 / 255, blue: 28 / 255)
    static let auroraRaised = Color(red: 25 / 255, green: 22 / 255, blue: 50 / 255)
    static let auroraViolet = Color(red: 163 / 255, green: 143 / 255, blue: 255 / 255)
    static let auroraPink = Color(red: 255 / 255, green: 158 / 255, blue: 196 / 255)
    static let auroraMint = Color(red: 124 / 255, green: 227 / 255, blue: 195 / 255)
    static let auroraSky = Color(red: 132 / 255, green: 202 / 255, blue: 255 / 255)
    static let auroraAmber = Color(red: 255 / 255, green: 205 / 255, blue: 140 / 255)

    static let cinemaInk = Color.auroraInk
    static let cinemaAccent = Color.auroraViolet
    static let cinemaLavender = Color.auroraPink

    /// Soft, readable secondary text tone used across the app.
    static let auroraTextSecondary = Color.white.opacity(0.62)
    static let auroraTextTertiary = Color.white.opacity(0.42)
}

extension LinearGradient {
    static let auroraPrimary = LinearGradient(
        colors: [Color.auroraViolet, Color.auroraPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let auroraCool = LinearGradient(
        colors: [Color.auroraSky, Color.auroraMint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let auroraWarm = LinearGradient(
        colors: [Color.auroraPink, Color.auroraAmber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Hairline highlight used on card borders.
    static let auroraVeil = LinearGradient(
        colors: [Color.white.opacity(0.26), Color.white.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Bottom scrim that keeps poster artwork readable.
    static let auroraScrim = LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.35), Color.black.opacity(0.86)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography

extension Font {
    static func auroraDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func auroraTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func auroraLabel(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func auroraBody(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Ambient background

/// Animated aurora field. Three soft light blooms drift slowly behind the
/// content, layered over a deep indigo base and finished with a vignette.
/// The motion is a single 15s ease so it never competes with the UI, and it is
/// skipped entirely when Reduce Motion is enabled.
struct CinemaBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.auroraVoid, Color.auroraInk, Color.auroraVoid],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let w = max(proxy.size.width, 1)
                let h = max(proxy.size.height, 1)
                ZStack {
                    blob(Color.auroraViolet.opacity(0.36), size: 340)
                        .offset(x: drift ? w * 0.26 : w * 0.04, y: drift ? -h * 0.26 : -h * 0.36)
                    blob(Color.auroraPink.opacity(0.26), size: 300)
                        .offset(x: drift ? -w * 0.26 : -w * 0.04, y: drift ? h * 0.16 : h * 0.02)
                    blob(Color.auroraSky.opacity(0.20), size: 280)
                        .offset(x: drift ? w * 0.16 : -w * 0.22, y: drift ? h * 0.38 : h * 0.50)
                }
                .frame(width: w, height: h)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.clear, Color.auroraVoid.opacity(0.62)],
                center: .center,
                startRadius: 90,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 76)
    }
}

// MARK: - Surfaces

/// Soft translucent card used instead of the previous Liquid Glass material.
/// A tinted gradient fill, a hairline top-left highlight and a two-layer shadow
/// (neutral + coloured bloom) give depth without any backdrop blur, which keeps
/// scrolling smooth and scrolling-heavy screens cheap to render.
struct AuroraSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color
    let glow: Bool
    let fill: Double

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.20 * fill),
                            tint.opacity(0.07 * fill),
                            Color.white.opacity(0.03 * fill)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 16, y: 10)
            .shadow(color: glow ? tint.opacity(0.24) : Color.clear, radius: 22, y: 6)
    }
}

/// Dark "smoke" chrome used over video, where a light surface would wash out.
struct AuroraSmoke<S: InsettableShape>: ViewModifier {
    let shape: S
    let strength: Double

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16 * strength),
                            Color.white.opacity(0.05 * strength)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .background { shape.fill(Color.black.opacity(0.34 + 0.22 * strength)) }
            .overlay { shape.strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.8) }
            .shadow(color: Color.black.opacity(0.38), radius: 14, y: 7)
    }
}

extension View {
    /// Rounded translucent card (app surfaces).
    func auroraCard(cornerRadius: CGFloat = 24, tint: Color = .auroraViolet, glow: Bool = false, fill: Double = 1) -> some View {
        modifier(AuroraSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            glow: glow,
            fill: fill
        ))
    }

    /// Same card, arbitrary shape.
    func auroraCard<S: InsettableShape>(in shape: S, tint: Color = .auroraViolet, glow: Bool = false, fill: Double = 1) -> some View {
        modifier(AuroraSurface(shape: shape, tint: tint, glow: glow, fill: fill))
    }

    /// Dark control chrome for the player.
    func auroraSmoke(strength: Double = 1) -> some View {
        modifier(AuroraSmoke(shape: Circle(), strength: strength))
    }

    func auroraSmoke<S: InsettableShape>(in shape: S, strength: Double = 1) -> some View {
        modifier(AuroraSmoke(shape: shape, strength: strength))
    }

    /// Coloured bloom used behind hero artwork and primary actions.
    func auroraHalo(_ tint: Color = .auroraViolet, radius: CGFloat = 26, opacity: Double = 0.35) -> some View {
        shadow(color: tint.opacity(opacity), radius: radius, y: radius * 0.35)
    }
}

// MARK: - Eyebrow / section label

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(LinearGradient.auroraPrimary)
                .frame(width: 15, height: 3)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(Color.auroraViolet.opacity(0.92))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Big gradient headline used for hero and launch typography.
struct AuroraGradientText: View {
    let text: String
    var font: Font = .auroraDisplay(30)
    var gradient: LinearGradient = .auroraPrimary

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(gradient)
    }
}

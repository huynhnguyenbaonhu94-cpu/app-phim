import SwiftUI

// MARK: - Palette
//
// "Studio" theme — the flat, editorial direction that replaced the Aurora
// gradient look.
//
// Three rules drive everything here:
//
//   1. Neutral near-black surfaces, so poster artwork is the only real colour on
//      screen. Colourful chrome competes with the artwork and makes a film
//      library look noisy.
//   2. Exactly one accent — warm gold — used for the primary action, the
//      selected tab and section markers. Nothing else is allowed to be coloured.
//   3. Flat fills with a hairline edge instead of gradients, glows and blurred
//      materials. Each gradient or shadow is an offscreen pass the compositor
//      repeats for every card, so removing them is both a visual and a
//      performance decision.
//
// The property names are kept (`auroraViolet` and friends) because every screen
// already references them; the values are what changed. The canonical names are
// added alongside so new code reads correctly.

extension Color {
    // Surfaces, darkest to lightest.
    static let auroraVoid = Color(red: 8 / 255, green: 8 / 255, blue: 10 / 255)
    static let auroraInk = Color(red: 14 / 255, green: 14 / 255, blue: 17 / 255)
    static let auroraRaised = Color(red: 23 / 255, green: 23 / 255, blue: 27 / 255)

    // The single accent, plus the semantic tones that are allowed to differ.
    static let auroraViolet = Color(red: 239 / 255, green: 183 / 255, blue: 90 / 255)   // gold
    static let auroraPink = Color(red: 201 / 255, green: 138 / 255, blue: 46 / 255)     // deep gold
    static let auroraMint = Color(red: 111 / 255, green: 211 / 255, blue: 168 / 255)    // live
    static let auroraSky = Color(red: 152 / 255, green: 162 / 255, blue: 179 / 255)     // slate
    static let auroraAmber = Color(red: 232 / 255, green: 132 / 255, blue: 60 / 255)    // warning

    /// Canonical aliases for new code.
    static let auroraAccent = Color.auroraViolet
    static let auroraAccentDeep = Color.auroraPink
    static let auroraSurface = Color.auroraRaised

    // Legacy names kept so older screens keep compiling.
    static let cinemaInk = Color.auroraInk
    static let cinemaAccent = Color.auroraViolet
    static let cinemaLavender = Color.auroraPink

    /// Text ramp. Three steps only: reading text, supporting text, hints.
    static let auroraTextPrimary = Color.white.opacity(0.95)
    static let auroraTextSecondary = Color.white.opacity(0.60)
    static let auroraTextTertiary = Color.white.opacity(0.38)

    /// Hairline used on every card edge.
    static let auroraHairline = Color.white.opacity(0.07)
}

extension LinearGradient {
    /// The accent ramp. Kept as a gradient because it is the single coloured
    /// surface in the app (primary buttons, the selected tab), but the two stops
    /// now sit close together so it reads as one warm tone rather than a
    /// two-colour effect.
    static let auroraPrimary = LinearGradient(
        colors: [Color.auroraViolet, Color.auroraAccentDeep],
        startPoint: .top,
        endPoint: .bottom
    )

    static let auroraCool = LinearGradient(
        colors: [Color.auroraSky, Color.auroraMint],
        startPoint: .top,
        endPoint: .bottom
    )

    static let auroraWarm = LinearGradient(
        colors: [Color.auroraViolet, Color.auroraAmber],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Hairline highlight. Flatter than before: a 1pt edge should not look like
    /// a lighting effect.
    static let auroraVeil = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Bottom scrim that keeps poster titles readable.
    static let auroraScrim = LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.30), Color.black.opacity(0.82)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography
//
// Plain SF rather than the rounded face. Headings lean on weight and tight
// tracking instead of shape, which reads calmer next to poster artwork and
// gives the app an editorial feel instead of a playful one.

extension Font {
    static func auroraDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    static func auroraTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func auroraLabel(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func auroraBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Ambient background

/// Flat backdrop: a near-black base with a single soft accent wash at the top.
///
/// The previous version stacked three 800pt radial blooms and a full-screen
/// vignette. Those are large offscreen fills that every tab re-composites, and
/// against a dark UI they mostly read as noise. One wash keeps the depth cue and
/// costs a fraction of the work.
struct CinemaBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.auroraVoid, Color.auroraInk],
            startPoint: .top,
            endPoint: .bottom
        )
        // The wash lives in an `overlay` so it never feeds its size back into the
        // layout: as a direct child of a `ZStack` a large radial gradient widens
        // the whole screen and pushes content off-centre.
        .overlay(alignment: .top) {
            RadialGradient(
                colors: [Color.auroraAccent.opacity(0.10), Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )
            .frame(height: 560)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

/// Flat card: one neutral fill, a whisper of the caller's tint and a 1pt edge.
///
/// No gradient fill, no drop shadow, no material. Cards appear by the dozen on
/// library and search screens, and each shadow was an offscreen pass per card
/// per frame. Depth now comes from the fill being lighter than the background,
/// which is how dark-mode elevation is meant to work anyway.
struct AuroraSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color
    let glow: Bool
    let fill: Double

    func body(content: Content) -> some View {
        content
            .background { shape.fill(Color.auroraRaised) }
            .background { shape.fill(tint.opacity(0.07 * fill)) }
            .overlay { shape.strokeBorder(tint.opacity(0.16), lineWidth: 1) }
            // Only hero surfaces ask for `glow`, and even then it stays short.
            .shadow(color: glow ? Color.black.opacity(0.34) : Color.clear, radius: glow ? 12 : 0, y: glow ? 6 : 0)
    }
}

/// Chrome used over video, where a light surface would wash out.
struct AuroraSmoke<S: InsettableShape>: ViewModifier {
    let shape: S
    let strength: Double

    func body(content: Content) -> some View {
        content
            .background { shape.fill(Color.black.opacity(0.42 + 0.20 * strength)) }
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
    }
}

extension View {
    /// Flat card (app surfaces).
    func auroraCard(cornerRadius: CGFloat = 20, tint: Color = .auroraAccent, glow: Bool = false, fill: Double = 1) -> some View {
        modifier(AuroraSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            glow: glow,
            fill: fill
        ))
    }

    /// Same card, arbitrary shape.
    func auroraCard<S: InsettableShape>(in shape: S, tint: Color = .auroraAccent, glow: Bool = false, fill: Double = 1) -> some View {
        modifier(AuroraSurface(shape: shape, tint: tint, glow: glow, fill: fill))
    }

    /// Dark control chrome for the player.
    func auroraSmoke(strength: Double = 1) -> some View {
        modifier(AuroraSmoke(shape: Circle(), strength: strength))
    }

    func auroraSmoke<S: InsettableShape>(in shape: S, strength: Double = 1) -> some View {
        modifier(AuroraSmoke(shape: shape, strength: strength))
    }

    /// Kept so existing screens compile. The coloured bloom is gone on purpose:
    /// a wide glow behind every hero and every primary button was one of the
    /// heaviest effects in the app for very little visual return. Accent fills
    /// carry the emphasis now.
    func auroraHalo(_ tint: Color = .auroraAccent, radius: CGFloat = 26, opacity: Double = 0.35) -> some View {
        self
    }
}

// MARK: - Eyebrow / section label

/// Small uppercase marker above a section title: one accent dash and a tracked
/// label. The gradient capsule and coloured glow are gone.
struct SectionEyebrow: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(Color.auroraAccent)
                .frame(width: 14, height: 2.5)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.auroraTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Headline used for hero and launch typography.
///
/// This used to paint a violet-to-pink gradient through the letterforms. The
/// text is now solid: on a neutral background the white headline is the
/// strongest element on the screen, and gradient type fights the poster artwork
/// sitting right next to it. The `gradient` parameter is kept so call sites do
/// not break, and is deliberately ignored.
struct AuroraGradientText: View {
    let text: String
    var font: Font = .auroraDisplay(30)
    var gradient: LinearGradient = .auroraPrimary

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color.auroraTextPrimary)
            .tracking(-0.4)
    }
}

import SwiftUI

// MARK: - Motion language
//
// Every interaction in the app uses one of four springs so movement feels
// consistent: `Motion.tap` for presses, `Motion.enter` for content arriving,
// `Motion.sheet` for panels and overlays, and `Motion.gentle` for ambient
// changes such as the background drift.

enum Motion {
    // Tuned short: every animation here either accompanies a tap or an entrance,
    // so long settle times read as input lag rather than polish.
    static let tap = Animation.spring(response: 0.24, dampingFraction: 0.74)
    static let enter = Animation.spring(response: 0.40, dampingFraction: 0.88)
    static let sheet = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.26)
}

// MARK: - Press feedback

struct AuroraPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var dimmed: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dimmed : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AuroraPressStyle {
    static var auroraPress: AuroraPressStyle { AuroraPressStyle() }
    static func auroraPress(scale: CGFloat) -> AuroraPressStyle { AuroraPressStyle(scale: scale) }
}

// MARK: - Edge-back drag

/// "Drag in from the left edge to go back" for screens that hide the navigation
/// bar, where UIKit disables the system gesture.
///
/// The drag progress lives in this modifier instead of on the screen itself: a
/// `@State` change only re-runs this small body, whereas keeping it on the
/// screen re-built the whole (heavy) detail layout on every frame of the drag.
struct EdgeBackDrag: ViewModifier {
    let onBack: () -> Void
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: progress * 18)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .global)
                    .onChanged { value in
                        guard value.startLocation.x <= 36,
                              value.translation.width > 0,
                              abs(value.translation.width) > abs(value.translation.height) else { return }
                        progress = min(1, value.translation.width / 120)
                    }
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        let shouldDismiss = value.startLocation.x <= 36
                            && horizontal >= 90
                            && horizontal > vertical * 1.25
                        progress = 0
                        if shouldDismiss { onBack() }
                    }
            )
    }
}

// MARK: - Entrance reveal

/// Staggered fade + rise used when a screen's content first appears.
struct AuroraReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                guard !reduceMotion else { shown = true; return }
                // Only the first screenful animates in. Cards that are built
                // later — while scrolling a long grid — appear instantly, so
                // scrolling never has to run an entrance animation on a whole row
                // of posters at once. That alone removed most of the stutter on
                // the long shelves.
                guard index <= 6 else { shown = true; return }
                withAnimation(Motion.enter.delay(Double(index) * 0.02)) {
                    shown = true
                }
            }
    }
}

extension View {
    func auroraReveal(_ index: Int = 0) -> some View {
        modifier(AuroraReveal(index: index))
    }

    /// Kept so existing screens compile. The scroll-linked scale/fade is gone on
    /// purpose: it ran a transform on every card for every frame of a scroll, and
    /// on a long shelf that is the most expensive thing the app can do while the
    /// user is simply browsing.
    func auroraScrollDepth() -> some View {
        self
    }
}

// MARK: - Shimmer

struct AuroraShimmerOverlay: View {
    @State private var phase: CGFloat = -1.2

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            LinearGradient(
                colors: [Color.clear, Color.white.opacity(0.28), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.65)
            .offset(x: phase * width * 1.8)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard phase < 0 else { return }
            withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

extension View {
    func auroraShimmer() -> some View {
        overlay { AuroraShimmerOverlay() }
    }
}

// MARK: - Loading skeletons

struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .auroraShimmer()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SkeletonPosterCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SkeletonBlock(cornerRadius: 22)
                .aspectRatio(0.69, contentMode: .fit)
            SkeletonBlock(cornerRadius: 6)
                .frame(height: 12)
                .frame(maxWidth: 130, alignment: .leading)
            SkeletonBlock(cornerRadius: 6)
                .frame(height: 9)
                .frame(maxWidth: 84, alignment: .leading)
        }
    }
}

struct SkeletonPosterGrid: View {
    var count: Int = 6
    var columns: Int = 2

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(columns, 1)),
            spacing: 20
        ) {
            ForEach(0..<max(count, 1), id: \.self) { _ in
                SkeletonPosterCard()
            }
        }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 13) {
            SkeletonBlock(cornerRadius: 14)
                .frame(width: 84, height: 56)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(cornerRadius: 6).frame(height: 12).frame(maxWidth: 160, alignment: .leading)
                SkeletonBlock(cornerRadius: 6).frame(height: 9).frame(maxWidth: 110, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .auroraCard(cornerRadius: 20, fill: 0.5)
    }
}

// MARK: - Live indicators

struct LivePulse: View {
    var color: Color = .auroraMint
    var size: CGFloat = 7
    /// The expanding ripple is opt-in. One animated indicator is a nice detail,
    /// but a whole grid of them keeps the render loop running at full rate
    /// forever, which makes the entire app — including tab switches — feel
    /// heavy. Grid cells therefore use the static dot.
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            if animated {
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: size, height: size)
                    .scaleEffect(animate ? 2.3 : 1)
                    .opacity(animate ? 0 : 0.9)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear {
            guard animated, !reduceMotion, !animate else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

struct EqualizerBars: View {
    var color: Color = .auroraViolet
    var bars: Int = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private let peaks: [CGFloat] = [9, 14, 6, 12, 8, 13]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<max(bars, 1), id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: animate ? peaks[index % peaks.count] : 4)
                    .animation(
                        .easeInOut(duration: 0.42 + Double(index) * 0.09).repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .frame(height: 15, alignment: .bottom)
        .onAppear {
            guard !reduceMotion, !animate else { return }
            animate = true
        }
    }
}

// MARK: - Chips

struct AuroraChip: View {
    let title: String
    var selected: Bool = false
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            chipLabel
        }
        .buttonStyle(.auroraPress(scale: 0.94))
        .animation(Motion.gentle, value: selected)
    }

    private var chipBody: some View {
        HStack(spacing: 5) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .transition(.opacity)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.auroraVoid : Color.auroraTextSecondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background { Capsule().fill(selected ? Color.auroraAccent : Color.white.opacity(0.06)) }
        .overlay { Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.07), lineWidth: 1) }
    }
}

// MARK: - Tab bar

enum CinemoraTab: Int, CaseIterable, Identifiable {
    case home, tv, library, search, saved

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Trang Chủ"
        case .tv: return "Truyền Hình"
        case .library: return "Thư Viện"
        case .search: return "Tìm Kiếm"
        case .saved: return "Lưu"
        }
    }

    var icon: String {
        switch self {
        case .home: return "sparkles.tv"
        case .tv: return "tv"
        case .library: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .saved: return "bookmark"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "sparkles.tv.fill"
        case .tv: return "tv.fill"
        case .library: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .saved: return "bookmark.fill"
        }
    }
}

/// Floating custom tab bar. The native bar is hidden so the selection pill can
/// morph between items with `matchedGeometryEffect` while each tab keeps its own
/// navigation state inside the system `TabView`.
struct AuroraTabBar: View {
    @Binding var selection: CinemoraTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CinemoraTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    // Plain assignment on purpose. Wrapping this in
                    // `withAnimation` also animated the content swap, cross-fading
                    // two full screens for the length of the spring. The pill
                    // still morphs, because the animation is applied to this
                    // bar's own subtree at the bottom.
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 17, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? Color.auroraVoid : Color.auroraTextTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.auroraAccent)
                                .matchedGeometryEffect(id: "auroraTabIndicator", in: indicator)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.auroraRaised.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.auroraHairline, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 14, y: 8)
        }
        .padding(.horizontal, 16)
        .animation(Motion.tap, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

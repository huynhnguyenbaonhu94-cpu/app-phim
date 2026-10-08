import SwiftUI
import UIKit

final class CinemoraAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

/// Programmatic orientation control, shared by the player and the TV tab.
enum OrientationSupport {
    static func rotate(to orientation: UIInterfaceOrientation) {
        let isLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        // The app delegate's orientation lock plus the scene geometry request
        // below are the supported way to force a rotation. There used to be a
        // third line here — `UIDevice.current.setValue(_:forKey:"orientation")` —
        // which is the old KVC hack. Apple moved `orientation` off `UIDevice`, so
        // on iOS 16+ that call is undefined behaviour and could raise at any time;
        // it ran on every player open/close, so the app crashed after a few uses.
        CinemoraAppDelegate.orientationLock = isLandscape ? .landscape : .portrait
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: isLandscape ? .landscape : .portrait)) { _ in }
        scene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// Rotates into landscape and only then presents the player, so it opens
    /// straight into landscape instead of appearing in portrait and spinning
    /// afterwards. The short wait is the rotation itself, which the user sees.
    /// `DispatchQueue.main` rather than a task: it keeps the helper free of any
    /// actor-isolation requirement, so every call site stays simple.
    static func rotateThenPresent(_ present: @escaping () -> Void) {
        rotate(to: .landscapeRight)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { present() }
    }
}

@main
@MainActor
struct CinemoraApp: App {
    @UIApplicationDelegateAdaptor(CinemoraAppDelegate.self) private var appDelegate
    @State private var store = CinemaStore()
    @State private var connectivity = ConnectivityMonitor()
    @State private var tvStore = TvStore()

    var body: some Scene {
        WindowGroup {
            CinemoraTabShell(store: store, tvStore: tvStore)
                .environment(store)
                .environment(connectivity)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Launch screen

private struct LaunchLoader: View {
    @State private var appear = false
    @State private var glow = false

    var body: some View {
        ZStack {
            CinemaBackground()

            VStack(spacing: 10) {
                ZStack {
                    // Soft radial gradients instead of blurred circles: same
                    // glow, but no offscreen blur pass while the app boots.
                    RadialGradient(
                        colors: [Color.auroraViolet.opacity(0.5), Color.auroraViolet.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(glow ? 1.12 : 0.86)
                    RadialGradient(
                        colors: [Color.auroraPink.opacity(0.4), Color.auroraPink.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110
                    )
                    .frame(width: 220, height: 220)
                    .offset(x: 26, y: -18)
                    .scaleEffect(glow ? 0.92 : 1.08)
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(LinearGradient.auroraPrimary)
                        .scaleEffect(appear ? 1 : 0.55)
                        .rotationEffect(.degrees(appear ? 0 : -14))
                }

                AuroraGradientText(text: "CINEMORA", font: .auroraDisplay(26))
                    .tracking(5)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 14)

                Text("PHIM HAY MỖI NGÀY")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .opacity(appear ? 1 : 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 124, height: 3)
                    Capsule()
                        .fill(LinearGradient.auroraPrimary)
                        .frame(width: appear ? 124 : 10, height: 3)
                        .auroraHalo(.auroraViolet, radius: 10, opacity: 0.6)
                }
                .padding(.top, 24)
            }
        }
        .zIndex(100)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.72)) { appear = true }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

// MARK: - Tab shell

@MainActor
struct CinemoraTabShell: View {
    /// Handed in explicitly instead of being observed with `@EnvironmentObject`:
    /// an observed store invalidates this view — and with it the whole tab
    /// container — on every published change.
    let store: CinemaStore
    let tvStore: TvStore
    @Environment(ConnectivityMonitor.self) private var connectivity
    @State private var selection: CinemoraTab = .home
    @State private var showLaunchLoader = true
    @State private var keyboardVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            AuroraTabHost(selection: $selection, store: store, tvStore: tvStore, connectivity: connectivity)
                .ignoresSafeArea()

            if !connectivity.isConnected {
                OfflineBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showLaunchLoader {
                LaunchLoader()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .overlay(alignment: .bottom) {
            AuroraTabBar(selection: $selection)
                .padding(.bottom, 2)
                // The bar rides above the software keyboard, which puts it right
                // on top of whatever form the user is filling in — the last rows
                // of the form end up hidden behind it. So while the keyboard is
                // up the bar parks itself just below the screen and comes back the
                // moment the keyboard leaves. It is never removed, only moved
                // aside, and the slide is the same spring as the rest of the app.
                .offset(y: keyboardVisible ? 140 : 0)
                .opacity(keyboardVisible ? 0 : 1)
                .allowsHitTesting(!keyboardVisible)
                .animation(Motion.sheet, value: keyboardVisible)
                .opacity(showLaunchLoader ? 0 : 1)
                .animation(Motion.enter, value: showLaunchLoader)
        }
        .animation(.easeInOut(duration: 0.28), value: connectivity.isConnected)
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeOut(duration: 0.45)) { showLaunchLoader = false }
        }
        // Combine's publisher is used rather than the async sequence: keyboard
        // notifications are posted on the main thread, and this form keeps the
        // handler free of any sendability question.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .background {
            ZStack {
                AccountSessionWatcher()
                // Closes the keyboard on a tap anywhere outside a text field.
                AuroraKeyboardDismissLayer()
            }
        }
    }
}

// MARK: - Tab container

/// Hosts the five tab roots in a container we own instead of SwiftUI's `TabView`.
///
/// `TabView` is backed by `UITabBarController`, and since iOS 18 that controller
/// animates every tab switch with a system cross-dissolve plus zoom. On content
/// as heavy as these screens, that animation is exactly what made switching tabs
/// feel laggy — and SwiftUI offers no way to turn it off. Here each tab is a
/// `UIHostingController` whose view is simply hidden or shown, so switching is a
/// visibility flip: instant, with no animation and no rebuild, while every tab
/// keeps its own state, scroll position and navigation stack.
final class AuroraTabHostController: UIViewController {
    private var hosts: [Int: UIViewController] = [:]
    private var selectedIndex = 0
    var makeHost: ((Int) -> UIViewController)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The first host is built before the container has a size, so pin every
        // host to the container on each layout pass.
        let bounds = view.bounds
        for host in hosts.values where host.view.frame != bounds {
            host.view.frame = bounds
        }
    }

    /// Shows the tab at `index`, building its host the first time it is needed.
    func select(_ index: Int) {
        guard index != selectedIndex || hosts[index] == nil else { return }
        let previous = hosts[selectedIndex]
        selectedIndex = index
        guard let host = host(at: index) else { return }
        for (key, value) in hosts where key != index {
            value.view.isHidden = true
            value.view.alpha = 1
        }
        host.view.isHidden = false
        if previous !== host {
            // Fade the incoming tab in so the swap reads as one motion with the
            // tab bar instead of a hard cut. Alpha only: no layout, no rebuild.
            host.view.alpha = 0
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                host.view.alpha = 1
            }
        }
    }

    /// Builds every other tab once, hidden, so the first visit to each is an
    /// instant visibility flip. Staggered so the launch stays responsive.
    func prewarm(excluding index: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            for target in 0..<CinemoraTab.allCases.count where target != index {
                guard let self, !Task.isCancelled else { return }
                _ = self.host(at: target)
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
    }

    private func host(at index: Int) -> UIViewController? {
        if let existing = hosts[index] { return existing }
        guard let makeHost else { return nil }
        let host = makeHost(index)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        host.view.isHidden = true
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hosts[index] = host
        return host
    }
}

/// SwiftUI bridge for `AuroraTabHostController`.
private struct AuroraTabHost: UIViewControllerRepresentable {
    @Binding var selection: CinemoraTab
    let store: CinemaStore
    let tvStore: TvStore
    let connectivity: ConnectivityMonitor

    func makeUIViewController(context: Context) -> AuroraTabHostController {
        let controller = AuroraTabHostController()
        let store = self.store
        let tvStore = self.tvStore
        let connectivity = self.connectivity
        controller.makeHost = { index in
            let host = UIHostingController(
                rootView: AuroraTabScreen(
                    tab: CinemoraTab.allCases[index],
                    store: store,
                    tvStore: tvStore,
                    connectivity: connectivity
                )
            )
            // A hosting controller created by hand does not inherit the SwiftUI
            // environment, so the app's dark appearance is applied explicitly.
            host.overrideUserInterfaceStyle = .dark
            host.view.backgroundColor = .clear
            return host
        }
        // Build the other tabs shortly after launch so the first switch to each
        // is a visibility flip instead of a cold render.
        controller.prewarm(excluding: CinemoraTab.allCases.firstIndex(of: selection) ?? 0)
        return controller
    }

    func updateUIViewController(_ controller: AuroraTabHostController, context: Context) {
        controller.select(CinemoraTab.allCases.firstIndex(of: selection) ?? 0)
    }
}

/// A tab's root: its own navigation stack, plus a swipe way back.
///
/// The stack lives here rather than in the host controller so the gesture below
/// can pop it. Every screen in this app hides the navigation bar, and with the
/// bar hidden UIKit disables the system interactive-pop gesture — which is why
/// going back used to mean reaching for the button.
private struct AuroraTabScreen: View {
    let tab: CinemoraTab
    let store: CinemaStore
    let tvStore: TvStore
    let connectivity: ConnectivityMonitor
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            root
                .environment(store)
                .environment(tvStore)
                .environment(connectivity)
                .navigationDestination(for: Movie.self) { movie in
                    MovieDetailScreen(slug: movie.slug)
                }
                .navigationDestination(for: SectionListRoute.self) { route in
                    SectionListScreen(kind: route.kind, title: route.title)
                }
        }
        .overlay(alignment: .leading) { backSwipeEdge }
    }

    @ViewBuilder
    private var root: some View {
        switch tab {
        case .home: HomeScreen()
        case .tv: TVScreen(store: store)
        case .library: LibraryScreen()
        case .search: SearchScreen()
        case .saved: SavedHubScreen()
        }
    }

    /// Invisible strip along the left edge: drag right from it to go back. It is
    /// inert while the stack is empty, so it never blocks content on a root tab.
    private var backSwipeEdge: some View {
        Color.clear
            .frame(width: 18)
            .contentShape(Rectangle())
            .allowsHitTesting(!path.isEmpty)
            .gesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .global)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        guard !path.isEmpty,
                              horizontal > 55,
                              horizontal > abs(value.translation.height) else { return }
                        path.removeLast()
                    }
            )
    }
}

// MARK: - Offline banner

/// Owns the account-session work for the whole app.
///
/// It deliberately lives in its own tiny view instead of on the tab shell: an
/// `@EnvironmentObject` invalidates its view on *every* published change, so
/// observing the store on the shell would re-evaluate the shell — and with it
/// the tab container — whenever the store changed. Here only this zero-sized
/// view is invalidated, which keeps tab switching smooth.
private struct AccountSessionWatcher: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .task {
                // Session restore runs in the background; the launch screen must
                // never wait for a slow/unavailable API before showing the app.
                await store.restoreAccount()
            }
            .task {
                // "Log out all devices" has to reach the other devices quickly,
                // so this polls often. It is cheap: one small request, and
                // `checkAccountSession()` only publishes when the user actually
                // changed, so idle polls cost nothing on screen.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled { await store.checkAccountSession() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Picking the device back up is the moment the user notices a
                // remote logout, so check immediately instead of waiting a tick.
                if phase == .active { Task { await store.checkAccountSession() } }
            }
    }
}

private struct OfflineBanner: View {

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.auroraAmber.opacity(0.2))
                    .frame(width: 34, height: 34)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.auroraAmber)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Không có kết nối Internet")
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                Text("Bật Wi-Fi hoặc dữ liệu di động để truy cập app.")
                    .font(.auroraBody(10))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .auroraCard(cornerRadius: 19, tint: .auroraAmber, glow: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Không có kết nối Internet. Bật Wi-Fi hoặc dữ liệu di động để truy cập app.")
    }
}

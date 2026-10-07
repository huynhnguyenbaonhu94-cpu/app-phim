import SwiftUI
import UIKit

final class CinemoraAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

@main
@MainActor
struct CinemoraApp: App {
    @UIApplicationDelegateAdaptor(CinemoraAppDelegate.self) private var appDelegate
    @StateObject private var store = CinemaStore()
    @StateObject private var connectivity = ConnectivityMonitor()

    var body: some Scene {
        WindowGroup {
            CinemoraTabShell()
                .environmentObject(store)
                .environmentObject(connectivity)
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
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var selection: CinemoraTab = .home
    @State private var showLaunchLoader = true

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selection) {
                tabRoot { HomeScreen() }
                    .tag(CinemoraTab.home)
                    .toolbar(.hidden, for: .tabBar)

                tabRoot { TVScreen() }
                    .tag(CinemoraTab.tv)
                    .toolbar(.hidden, for: .tabBar)

                tabRoot { LibraryScreen() }
                    .tag(CinemoraTab.library)
                    .toolbar(.hidden, for: .tabBar)

                tabRoot { SearchScreen() }
                    .tag(CinemoraTab.search)
                    .toolbar(.hidden, for: .tabBar)

                tabRoot { SavedHubScreen() }
                    .tag(CinemoraTab.saved)
                    .toolbar(.hidden, for: .tabBar)
            }
            .tint(.auroraViolet)

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
                .opacity(showLaunchLoader ? 0 : 1)
                .animation(Motion.enter, value: showLaunchLoader)
        }
        .animation(.easeInOut(duration: 0.28), value: connectivity.isConnected)
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeOut(duration: 0.45)) { showLaunchLoader = false }
        }
        .background { AccountSessionWatcher() }
    }

    private func tabRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Movie.self) { movie in
                    MovieDetailScreen(slug: movie.slug)
                }
        }
    }
}

// MARK: - Offline banner

/// Owns the account-session work for the whole app.
///
/// It deliberately lives in its own tiny view instead of on the tab shell: an
/// `@EnvironmentObject` invalidates its view on *every* published change, so
/// observing the store on the shell re-created the whole `TabView` (and all five
/// tab roots) whenever the store changed. Here only this zero-sized view is
/// invalidated, which keeps tab switching smooth.
private struct AccountSessionWatcher: View {
    @EnvironmentObject private var store: CinemaStore

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
                // Session checks only need to catch revoked sessions, so a slow
                // timer is enough. Every poll that changes state makes each tab
                // re-render, so keep the interval generous.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    if !Task.isCancelled { await store.checkAccountSession() }
                }
            }
    }
}

private struct OfflineBanner: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.auroraAmber.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulse ? 1.12 : 0.94)
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

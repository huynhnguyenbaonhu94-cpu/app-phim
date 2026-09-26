import SwiftUI

@main
@MainActor
struct CinemoraApp: App {
    @StateObject private var store = CinemaStore()
    @StateObject private var connectivity = ConnectivityMonitor()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024, diskPath: "cinemora-images")
    }

    var body: some Scene {
        WindowGroup {
            CinemoraTabShell()
                .environmentObject(store)
                .environmentObject(connectivity)
                .preferredColorScheme(.dark)
        }
    }
}

private struct LaunchLoader: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.cinemaInk.ignoresSafeArea()
            Circle().fill(Color.cinemaAccent.opacity(0.08)).frame(width: 260, height: 260).blur(radius: 22)
            VStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(Color.cinemaAccent)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.78 : 1)
                Text("CINEMORA").font(.system(size: 24, weight: .black, design: .rounded)).tracking(3).foregroundStyle(.white)
                Text("PHIM HAY MỖI NGÀY").font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(.white.opacity(0.52))
                Capsule().fill(Color.cinemaAccent).frame(width: 88, height: 3).opacity(pulse ? 0.7 : 1).padding(.top, 20)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) { pulse = true } }
        .zIndex(100)
    }
}

@MainActor
struct CinemoraTabShell: View {
    @EnvironmentObject private var store: CinemaStore
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunchLoader = true

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                tabRoot {
                    HomeScreen()
                }
                .tabItem { Label("Trang Chủ", systemImage: "sparkles.tv") }

                tabRoot {
                    LibraryScreen()
                }
                .tabItem { Label("Thư Viện", systemImage: "square.grid.2x2") }

                tabRoot {
                    SearchScreen()
                }
                .tabItem { Label("Tìm Kiếm", systemImage: "magnifyingglass") }

                tabRoot {
                    AccountScreen()
                }
                .tabItem { Label("Tài Khoản", systemImage: "person.crop.circle") }
            }
            .tint(.cinemaAccent)
            .modifier(ScrollMinimizingTabBar())

            if !connectivity.isConnected {
                OfflineBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showLaunchLoader { LaunchLoader().transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.25), value: connectivity.isConnected)
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeOut(duration: 0.38)) { showLaunchLoader = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshHome() } }
        }
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

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Không có kết nối Internet")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Bật Wi-Fi hoặc dữ liệu di động để truy cập app.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.yellow.opacity(0.35), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Không có kết nối Internet. Bật Wi-Fi hoặc dữ liệu di động để truy cập app.")
    }
}

private struct ScrollMinimizingTabBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content
    }
}

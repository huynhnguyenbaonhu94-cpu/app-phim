import SwiftUI

@main
@MainActor
struct CinemoraApp: App {
    @StateObject private var store = CinemaStore()

    var body: some Scene {
        WindowGroup {
            CinemoraTabShell()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
struct CinemoraTabShell: View {
    var body: some View {
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

private struct ScrollMinimizingTabBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

# Ghi chú: vì sao chuyển tab bị lag trên iOS 18/26

## Kết luận

Từ **iOS 18**, `UITabBarController` mặc định chạy một hiệu ứng chuyển tab của hệ thống
(cross-dissolve kèm zoom) mỗi lần đổi tab. Trước iOS 18 việc đổi tab là tức thì, không có
animation nào. `TabView` của SwiftUI được dựng trên `UITabBarController`, nên nó thừa hưởng
hiệu ứng này, và **SwiftUI không có API nào để tắt nó**.

Với nội dung nặng như các màn hình của Cinemora, chính hiệu ứng đó tạo cảm giác "lag, không
mượt" khi bấm tab: toàn bộ màn hình mới bị scale + fade trong lúc cây view của nó vẫn đang
được dựng lần đầu.

## Nguồn tham khảo

- Medium — *New TabBarController Transition Animation in iOS 18 and Xcode 16*
  <https://medium.com/@adityaramadhan.biz/new-tabbar-transition-animation-in-ios-18-and-xcode-16-ea4b2c4d84d4>
  Xác nhận animation mới của iOS 18 và đưa ra cách tắt bằng
  `UIView.transition(from:to:duration: 0, options: [.transitionCrossDissolve])`
  trong `tabBarController(_:shouldSelect:)`.

- Reddit r/SwiftUI — *Persistent "Jump" animation glitch in SwiftUI TabView when switching tabs*
  <https://www.reddit.com/r/SwiftUI/comments/1tgxuhq/persistent_jump_animation_glitch_in_swiftui/>
  Người dùng mô tả đúng triệu chứng: "mỗi lần đổi tab, view mới không hiện ra ngay mà có vẻ
  chạy hiệu ứng scale 0→1 / fade-in với expansion", và xác nhận đã thử mà **không** sửa được bằng:
  `withAnimation` removal, `.animation(nil, value:)`, `.transaction { $0.animation = nil }`,
  `.toolbar(.hidden, for: .tabBar)`, `UITabBar.appearance().isHidden`, hay bỏ `ignoresSafeArea()`.
  Tức là không thể tắt bằng modifier SwiftUI — phải can thiệp ở tầng UIKit.

- StackOverflow — *iOS 18 tab switch flashes screen*
  <https://stackoverflow.com/questions/79006130/ios-18-tab-switch-flashes-screen>
  Cùng nguyên nhân, với `UITabBarController` chuẩn.

- Apple Developer Forums — *Liquid Glass TabBar animations causes Hangs, bug*
  <https://developer.apple.com/forums/thread/809465>
  Trên iOS 26, animation của tab bar kiểu Liquid Glass còn gây treo app.

## Cách khắc phục đã áp dụng

Thay `TabView` bằng container riêng `AuroraTabHostController` (trong `CinemoraApp.swift`):
mỗi tab là một `UIHostingController` được thêm làm child view controller một lần, và việc
đổi tab chỉ là bật/tắt `view.isHidden`. Nhờ vậy:

- Không còn `UITabBarController` ⇒ không còn hiệu ứng chuyển tab của hệ thống.
- Đổi tab là một phép đổi visibility ⇒ tức thì, không animation, không dựng lại cây view.
- Mỗi tab vẫn giữ nguyên state, vị trí cuộn và `NavigationStack` như trước.
- Bỏ luôn `.toolbar(.hidden, for: .tabBar)` vì không còn tab bar hệ thống.

Lưu ý khi bảo trì: `UIHostingController` tạo thủ công **không** thừa hưởng environment của
SwiftUI, nên phải tự gán `.environmentObject(store)` và `overrideUserInterfaceStyle = .dark`.

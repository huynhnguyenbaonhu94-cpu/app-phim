# Cinemora — Thiết kế lại giao diện theo hệ thống **Aurora**

Tài liệu này mô tả toàn bộ thay đổi giao diện của app SwiftUI: bỏ lớp **Liquid Glass** cũ và thay bằng hệ thống **Aurora** — nhẹ, mượt, có chuyển động nhưng không nặng máy.

## 1. Vì sao bỏ Liquid Glass

| Vấn đề của giao diện cũ | Cách Aurora xử lý |
| --- | --- |
| `glassEffect` / `Material` là API iOS 26 (hoặc material fallback) → phải rẽ nhánh `if #available`, blur theo thời gian thực tốn GPU khi cuộn danh sách dài | Surface tự vẽ bằng gradient + viền sáng, **không blur runtime**, chỉ một `LinearGradient` mỗi lớp → cuộn 60/120 fps ổn định |
| Màu sắc rời rạc (`cinemaInk`, `cinemaAccent`, `cinemaLavender`) | Token ngữ nghĩa `auroraVoid/Ink/Raised` + dải nhấn `Violet/Pink/Mint/Sky/Amber` |
| Animation rải rác trong từng view, mỗi nơi một `spring` khác nhau | Một nguồn duy nhất `Motion` + modifier `.auroraReveal()` dùng chung |
| Không có trạng thái tải (skeleton), màn hình trắng khi chờ API | `SkeletonBlock` / `SkeletonPosterGrid` / `SkeletonRow` có hiệu ứng shimmer |

## 2. Hệ thống thiết kế mới

### 2.1 Màu & nền — `Design/CinemoraStyle.swift`

- Nền `CinemaBackground`: 4 lớp gradient tĩnh (nền ink → 3 vệt aurora mờ) + vignette. Tất cả là `LinearGradient`/`RadialGradient` tĩnh, **không animate**, nên không tốn GPU.
- Token: `auroraVoid` (nền sâu), `auroraInk`, `auroraRaised` (surface nổi), nhấn `auroraViolet`, `auroraPink`, `auroraMint`, `auroraSky`, `auroraAmber`; chữ `auroraTextSecondary/Tertiary`.
- Typography: `auroraDisplay` (tiêu đề lớn, rounded + tracking âm), `auroraTitle`, `auroraLabel`, `auroraBody`.
- Modifier surface:
  - `.auroraCard(cornerRadius:tint:glow:fill:)` — card gradient 2 lớp + viền sáng 0.7–1.4pt + đổ bóng; `glow: true` thêm quầng màu cho item đang chọn.
  - `.auroraSmoke(strength:)` — control nổi trên video (nút tròn, capsule).
  - `.auroraHalo(_:radius:opacity:)` — quầng sáng cho CTA.

### 2.2 Chuyển động — `Design/AuroraMotion.swift`

- `Motion.tap` (0.28/0.72), `Motion.enter` (0.52/0.86), `Motion.sheet` (0.42/0.82), `Motion.gentle` (easeInOut 0.32).
- `.buttonStyle(.auroraPress)` / `.auroraPress(scale:)`: nhún nhẹ + giảm độ sáng khi nhấn — áp dụng cho **mọi** nút trong app.
- `.auroraReveal(index)`: mỗi khối fade + dịch lên 16pt + scale 0.985, delay so le `index * 45ms`, tự tắt khi bật *Reduce Motion*.
- `.auroraShimmer()`: dải sáng chạy ngang cho skeleton.
- `LivePulse` (chấm nhịp cho kênh trực tiếp / thiết bị online), `EqualizerBars` (sóng nhạc khi kênh đang phát), `AuroraChip` (chip lọc có gradient khi chọn).
- `AuroraTabBar`: thanh tab tự vẽ, chỉ báo trượt bằng `matchedGeometryEffect`, icon `symbolEffect(.bounce)` khi đổi tab, rung `sensoryFeedback(.selection)`.

### 2.3 Component dùng chung — `Design/CinemaComponents.swift`

`CinemaHeader`, `SectionHeading`, `SectionEyebrow`, `AuroraGradientText`, `PosterArt` (async load + cache NSCache + shimmer khi chờ), `MoviePosterCard`, `MovieShelfCard`, `MovieShelf`, `FeaturedMovieCard`, `StateMessage`, `AuroraPrimaryButton`, `AuroraGhostButton`, `AuroraBackButton`.

## 3. Thay đổi theo từng màn hình

### Khung app — `CinemoraApp.swift`
- Màn khởi động mới: logo aurora phóng nhẹ + vòng sáng lan + thanh tiến trình, tan biến mượt vào app.
- Thanh tab tuỳ biến `AuroraTabBar` (ẩn tab bar hệ thống) với chỉ báo trượt, bounce icon, rung nhẹ.

### Trang chủ — `HomeScreen.swift`
- Hero lớn 430pt có **parallax theo cuộn** (ảnh dịch chậm hơn nội dung), badge chất lượng, nút "Xem ngay" có quầng sáng, nút yêu thích có hiệu ứng đổi icon.
- Shelf ngang bo tròn 26pt, card 210×130, reveal so le, snap theo từng card.

### Thư viện — `LibraryScreen.swift`
- Chip thể loại cuộn ngang (12 nhóm) với gradient khi chọn.
- **Bộ lọc nâng cao dạng gấp/mở**: nút có badge đếm số lọc đang bật, xoay chevron, panel bung ra bằng spring; nút "xóa lọc" riêng bên cạnh.
- Grid poster 2 cột, skeleton khi tải, tự nạp thêm khi cuộn gần cuối, "đã hiển thị hết kết quả".

### Tìm kiếm — `SearchScreen.swift`
- Ô tìm kiếm có **vòng sáng khi focus**, phóng nhẹ 1.2%, nút gửi chuyển gradient ↔ xám theo trạng thái hợp lệ.
- Bộ lọc & sắp xếp gấp/mở; đếm kết quả dùng `contentTransition(.numericText())`.
- Bàn phím tự ẩn khi cuộn (`scrollDismissesKeyboard(.interactively)`).

### Chi tiết phim — `MovieDetailScreen.swift`
- Hero 440pt: ảnh nền + scrim 3 lớp, tên phim 30pt có bóng, chip năm/thời lượng/ngôn ngữ/điểm, CTA "Xem phim" phát sáng, nút yêu thích nổi.
- Khối nội dung, 3 thẻ số liệu (đánh giá / lượt xem / cập nhật), dàn diễn viên cuộn ngang, chọn server + **lưới tập có gradient khi chọn**, 2 bảng metadata.
- Giữ nguyên: tự phát khi vào từ "Xem tiếp", vuốt cạnh trái để quay lại, điều hướng sang phim liên quan.

### Truyền hình — `TVScreen.swift`
- Kênh trực tiếp dạng **lưới card 2 cột** với badge LIVE nhấp nháy, hiệu ứng sóng khi đang phát, viền phát sáng khi chọn.
- Video đã đăng: hàng có badge "NỔI BẬT", card phát sáng và nhịp thở nếu admin bật hiệu ứng `pulse`, gắn sao nếu `ribbon`.
- Trình phát TV: control dạng smoke, panel chọn tỷ lệ khung hình, nút PiP đổi màu theo trạng thái, thanh tiến trình gradient.
- Toàn bộ logic phát (HLS, audio track riêng, đồng bộ live, SSE, PiP) **giữ nguyên**.

### Kho lưu — `LocalLibraryScreens.swift`
- `SavedHubScreen`: thẻ tài khoản phát sáng + 6 điểm đến có icon màu riêng, hiệu ứng nhấn nhún.
- `WatchHistoryScreen`: poster + **thanh tiến độ gradient** theo thời lượng đã xem, nút xoá từng mục, xoá tất cả.
- `FavoritesScreen`: lưới poster có badge chất lượng, nút bỏ yêu thích nổi trên ảnh.
- `PlaybackDefaultsScreen`: card cài đặt với icon màu, toggle gradient.

### Tài khoản — `AccountSettingsScreen.swift`
- **Segmented control tự vẽ** với chỉ báo trượt `matchedGeometryEffect`.
- Ô nhập có vòng sáng theo focus; khối lỗi màu hổ phách; nút CTA gradient có trạng thái loading.
- Danh sách thiết bị có chấm online nhấp nháy, nhãn ONLINE/OFFLINE, nút đăng xuất riêng.
- Sheet đổi mật khẩu và QR login được thiết kế lại; logic QR (tạo/duyệt/hết hạn) giữ nguyên.

### QR đăng nhập — `QRLoginViews.swift`
- QR trên card trắng có quầng sáng, **vệt scan chạy lên xuống**, thanh đếm ngược đổi màu khi gần hết hạn, dấu tick xanh khi thành công.

### Yêu cầu phim — `MovieRequestScreen.swift`
- Chip mức ưu tiên có icon, `TextEditor` bo tròn theo focus, chọn ảnh bằng `PhotosPicker` với preview và nút gỡ ảnh.

### Phụ đề — `SubtitlePreferencesScreen.swift`
- Preview realtime, slider/color picker có icon màu, nút đặt lại mặc định. Dùng chung cho cả màn Lưu và panel trong player.

### Xem tiếp — `ResumeMovieScreen.swift`
- Vòng tròn aurora quay + logo play nhịp thở khi đang tải nguồn; giữ nguyên logic khôi phục tập/nguồn.

### Trình phát phim — `Player/CinemaPlayerScreen.swift`
- Thanh trên/dưới, nút play lớn gradient có quầng, panel cài đặt dạng side-panel bo 26pt, panel chọn tập/nguồn dạng bottom-sheet, HUD chỉnh sáng/âm lượng màu aurora.
- **Không đổi**: AVPlayer/HLS, phụ đề, tốc độ phát, hẹn giờ tắt, dừng ở tập, PiP, vuốt dọc chỉnh sáng/âm lượng, gợi ý phim liên quan, lưu tiến độ.

## 4. Hiệu năng & khả năng truy cập

- Không dùng `Material`/`glassEffect` → bỏ blur runtime, bỏ nhánh `#available` phức tạp.
- Gradient và shadow đều tĩnh; chỉ animate `opacity`, `scale`, `offset`, `rotation` (thuộc tính rẻ cho GPU).
- `.auroraReveal` chỉ chạy một lần cho mỗi khối (không lặp khi cuộn).
- `LivePulse`, `EqualizerBars`, `auroraShimmer`, `auroraReveal` tự tắt khi bật *Reduce Motion*.
- Ảnh poster vẫn dùng `NSCache` + `URLCache` như trước, nay thêm shimmer khi chờ.

## 5. Việc cần kiểm tra trên macOS/Xcode

Sandbox Ubuntu chỉ có trình phân tích cú pháp Swift (tree-sitter, 23/23 file hợp lệ) — **không thể build iOS**. Cần chạy trên macOS:

```sh
brew install xcodegen
cd mobile-swiftui
xcodegen generate
open Cinemora.xcodeproj
```

Ưu tiên kiểm tra: `AuroraTabBar` trên iPhone có notch, hero parallax khi cuộn nhanh, panel cài đặt trong player ở chế độ ngang, và hiệu ứng `symbolEffect` khi bật *Reduce Motion*.

## 6. Sửa lỗi build trên Codemagic (Xcode 26.6, iOS SDK 26.5)

Lần archive đầu tiên thất bại với 3 lỗi biên dịch, đều nằm trong lớp design mới và đã được sửa:

| Lỗi | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| `AuroraMotion.swift:357` — `incorrect argument label in call (have '_:value:', expected '_:trigger:')` | API `sensoryFeedback` dùng nhãn `trigger:`, không phải `value:` | `.sensoryFeedback(.selection, trigger: selection)` |
| `CinemoraStyle.swift:169` — `value of type 'S' has no member 'strokeBorder'` | `strokeBorder` chỉ có trên `InsettableShape`, nhưng `AuroraSurface` ràng buộc `S: Shape` | Đổi ràng buộc thành `S: InsettableShape` |
| `CinemoraStyle.swift:196` — lỗi tương tự trong `AuroraSmoke` | Như trên | Đổi `AuroraSmoke` và hai hàm `auroraCard(in:)`, `auroraSmoke(in:)` sang `S: InsettableShape` |

Mọi nơi gọi `.auroraCard(in:)` / `.auroraSmoke(in:)` đều truyền `Circle()`, `Capsule()` hoặc `RoundedRectangle(...)` — tất cả đều là `InsettableShape` nên không cần sửa call site.

Sau khi sửa, đã quét lại toàn bộ project: 23/23 file hợp lệ về cú pháp, và mọi token thiết kế được dùng (`Color.aurora*`, `LinearGradient.aurora*`, `Font.aurora*`, `Motion.*`, modifier `aurora*`) đều tồn tại trong định nghĩa.

## 7. Sửa hiện tượng lag khi chuyển tab

`TabView` giữ **tất cả** tab đã mở trong bộ nhớ, nên mọi thứ đặt trong màn hình vẫn tiếp tục được vẽ và cập nhật kể cả khi tab đó không hiển thị. Có 6 nguồn gây lag, đã sửa hết:

| # | Nguyên nhân | Vì sao gây lag | Cách sửa |
| --- | --- | --- | --- |
| 1 | `CinemaBackground` dùng 3 hình tròn `.blur(radius: 76)` + animation `repeatForever` 15s | Blur phải render offscreen, và animation chạy **mãi mãi, ở mọi tab đã mở**. Đây là nguyên nhân nặng nhất | Thay bằng `RadialGradient` (cùng vẻ mềm, không cần blur) và bỏ hoàn toàn animation nền → nền tĩnh, Core Animation cache được |
| 2 | Màn khởi động dùng 2 hình tròn `.blur()` | Blur chạy đúng lúc app đang dựng màn hình đầu | Đổi sang `RadialGradient`, giữ nguyên hiệu ứng phóng nhẹ |
| 3 | `checkAccountSession()` gán `accountUser` mỗi **5 giây** | Gán lại giá trị y hệt vẫn phát `objectWillChange`, khiến **cả 5 tab re-render** mỗi 5 giây | Chỉ gán khi user thật sự đổi; giãn chu kỳ 5s → 20s |
| 4 | `tvVideoRefreshTask` gán `tvVideos` mỗi **12 giây**; `applyTvEvent` gán `tvStreams` mỗi sự kiện SSE | Cùng cơ chế: publish → mọi tab re-render, kể cả khi dữ liệu không đổi | Chỉ gán khi dữ liệu khác (`!=`); giãn chu kỳ 12s → 45s |
| 5 | `LibraryScreen` gọi `loadCatalog(reset: true)` mỗi lần tab hiện lại | `.task` chạy lại mỗi lần tab được chọn → **xoá sạch lưới phim**, hiện skeleton rồi tải lại | Thêm `loadIfNeeded()`: chỉ tải lại khi bộ lọc đổi, lưới rỗng, hoặc dữ liệu cũ hơn 180s |
| 6 | `TVScreen.onDisappear` gọi `stopTvLiveUpdates()` | Rời tab là ngắt SSE; quay lại tab là fetch lại 2 danh sách + mở lại SSE | Chỉ ngắt kết nối khi app xuống background (`scenePhase != .active`), không ngắt khi đổi tab |

Thêm hai thay đổi về cấu trúc và chi phí vẽ:

- **`CinemoraTabShell` không còn `@EnvironmentObject store`.** Một `@EnvironmentObject` làm view chứa nó bị invalidate mỗi khi store publish, bất kể body có đọc thuộc tính đó hay không. Trước đây điều này tái tạo toàn bộ `TabView` cùng 5 tab root mỗi lần store đổi. Phần restore/kiểm tra session được chuyển sang `AccountSessionWatcher` — một view 0×0 riêng biệt, nên chỉ nó bị invalidate.
- **`.auroraCard` chỉ vẽ 1 bóng thay vì 2.** Quầng màu (bóng thứ hai) chỉ được thêm khi `glow: true`; trước đây bóng thứ hai luôn tồn tại với màu trong suốt, vẫn tốn một lượt render offscreen cho mỗi card trong danh sách/lưới.
- **Hiệu ứng xuất hiện so le được rút ngắn**: delay tối đa từ `14 × 45ms = 630ms` xuống `8 × 28ms = 224ms`, nên nội dung "đứng yên" nhanh hơn nhiều sau khi chuyển tab.

Kết quả: khi chuyển tab, không còn blur toàn màn hình phải vẽ lại, không còn fetch lại dữ liệu, không còn vòng publish định kỳ 5–12 giây, và không còn re-render cả cây `TabView` mỗi khi store thay đổi. Các hiệu ứng chuyển động vẫn giữ nguyên: chỉ báo tab trượt, icon bounce, press scale, reveal, shimmer, skeleton, pulse/equalizer ở tab Truyền hình.

## 8. Vòng sửa thứ hai: chuyển tab vẫn còn lag

Sau vòng 7, chuyển tab vẫn còn giật và có độ trễ. Nguyên nhân chính lần này nằm ở **cách chuyển tab** và **cách giải mã ảnh poster**.

| # | Nguyên nhân | Vì sao gây lag | Cách sửa |
| --- | --- | --- | --- |
| 1 | `AuroraTabBar` đổi tab bằng `withAnimation(Motion.sheet) { selection = tab }` | Bọc animation quanh thay đổi `selection` cũng làm `TabView` **cross-fade toàn bộ nội dung** hai màn hình trong suốt thời gian của spring (~0,6s). Đây chính là cảm giác "lag và delay" khi bấm tab | Gán thẳng `selection = tab`; chuyển animation xuống chính thanh tab bằng `.animation(Motion.tap, value: selection)` nên viên chỉ báo vẫn trượt mượt mà nội dung đổi tức thì |
| 2 | `PosterArt` giải mã ảnh bằng `UIImage(data:)` **trên main thread** | Ảnh poster giữ nguyên độ phân giải gốc (~13 MB mỗi ảnh khi giải mã ở 3x) và chỉ được giải nén khi vẽ lần đầu — tức là **trên main thread, đúng lúc lưới đang render**. Một lưới 16 poster vừa ngốn hàng trăm MB vừa chặn main thread | Chuyển sang `CGImageSourceCreateThumbnailAtIndex` trong `Task.detached`: giải mã + hạ mẫu ở luồng nền, đúng cỡ hiển thị (240–1400 px), kèm `kCGImageSourceShouldCacheImmediately`. Cache cũng kiểm tra ảnh đã đủ lớn chưa trước khi dùng lại |
| 3 | Placeholder poster dùng `Circle().blur(radius: 34)` | Mỗi poster chưa tải xong là một lớp blur phải composite offscreen; một lưới đang tải là hàng chục lớp blur | Đổi sang `RadialGradient` |
| 4 | Mỗi kênh trong lưới Truyền hình có một `LivePulse` chạy `repeatForever` | Một lưới 10–16 kênh giữ render loop chạy 60fps **mãi mãi**, làm cả app (kể cả lúc chuyển tab) nặng | Thêm cờ `animated` (mặc định `false`): lưới dùng chấm tĩnh, chỉ thẻ nổi bật và overlay trình phát còn nhịp lan toả |
| 5 | `HeroParallax` đọc vị trí cuộn qua `GeometryReader` | Mỗi frame cuộn đều kéo theo một lượt layout lại toàn bộ thẻ hero | Chuyển sang `.visualEffect { content, proxy in … }` (iOS 17): đọc hình học trong render tree, không còn layout pass mỗi frame |
| 6 | Bóng thứ hai luôn tồn tại với màu trong suốt (`AuroraChip`, thẻ kênh) | Vẫn tốn một lượt shadow pass dù không nhìn thấy | Chỉ thêm bóng khi thực sự cần (`AuroraChip`), và đặt `radius: 0` khi không chọn (thẻ kênh) |

Ngoài ra toàn bộ spring đã được rút ngắn vì chúng đi kèm thao tác chạm hoặc lúc nội dung xuất hiện, nên thời gian ổn định dài bị cảm nhận là độ trễ:

| Token | Trước | Sau |
| --- | --- | --- |
| `Motion.tap` | `response 0.28` | `response 0.24` |
| `Motion.enter` | `response 0.52` | `response 0.40` |
| `Motion.sheet` | `response 0.42` | `response 0.34` |
| `Motion.gentle` | `0.32s` | `0.26s` |

Kết quả: bấm tab là nội dung đổi ngay (không còn cross-fade toàn màn hình), ảnh poster được giải mã ở luồng nền với dung lượng nhỏ hơn khoảng 8–10 lần, không còn lớp blur nào trong lưới, không còn hàng chục animation chạy vô hạn, và việc cuộn ở tab Trang chủ không còn sinh layout pass mỗi frame.

## 9. Vòng sửa thứ ba: nguyên nhân gốc của việc chuyển tab bị lag

Hai vòng trước đã cắt được phần lớn chi phí render, nhưng cảm giác lag khi bấm tab vẫn còn.
Nguyên nhân thật nằm ở **chính hệ thống**, không phải ở code của app.

### Nguyên nhân

Từ **iOS 18**, `UITabBarController` mặc định chạy một hiệu ứng chuyển tab của hệ thống
(cross-dissolve kèm zoom) mỗi lần đổi tab. Trước iOS 18, đổi tab là tức thì và không có
animation nào. `TabView` của SwiftUI được dựng trên `UITabBarController`, nên nó thừa hưởng
hiệu ứng này — và **SwiftUI không có API nào để tắt nó**.

Với các màn hình nặng như của Cinemora, hiệu ứng đó tạo đúng cảm giác "lag, không mượt":
toàn bộ màn hình mới bị scale và fade trong lúc cây view của nó vẫn đang được dựng lần đầu.

Đã kiểm chứng bằng tài liệu và báo cáo của cộng đồng (xem `NOTES-tab-transition.md` trong repo):

- Medium — *New TabBarController Transition Animation in iOS 18 and Xcode 16*: xác nhận
  animation mới và cách tắt ở tầng UIKit.
- Reddit r/SwiftUI — *Persistent "Jump" animation glitch in SwiftUI TabView*: mô tả đúng
  triệu chứng này và xác nhận **không** sửa được bằng bất kỳ modifier SwiftUI nào
  (`.animation(nil, value:)`, `.transaction { $0.animation = nil }`,
  `.toolbar(.hidden, for: .tabBar)`, `UITabBar.appearance().isHidden`, bỏ `ignoresSafeArea()`).
- Apple Developer Forums — *Liquid Glass TabBar animations causes Hangs*: trên iOS 26,
  animation của tab bar còn gây treo app.

### Cách sửa

Bỏ hẳn `TabView`, thay bằng container riêng `AuroraTabHostController` (trong `CinemoraApp.swift`).
Mỗi tab là một `UIHostingController` được thêm làm child view controller **một lần**, và đổi tab
chỉ là bật/tắt `view.isHidden`:

| | Trước (`TabView`) | Sau (`AuroraTabHostController`) |
| --- | --- | --- |
| Đổi tab là gì | `UITabBarController` đổi selected view controller | `isHidden` của hai hosting view |
| Animation | Hiệu ứng cross-dissolve + zoom của hệ thống | Không có |
| Dựng lại cây view | Có thể, mỗi lần đổi | Không |
| State, vị trí cuộn, `NavigationStack` | Giữ | Giữ |
| `.toolbar(.hidden, for: .tabBar)` | Cần, để giấu tab bar hệ thống | Không cần, vì không còn tab bar hệ thống |

Thanh tab dưới vẫn là `AuroraTabBar` tự vẽ, giữ nguyên viên chỉ báo morph, icon bounce và haptic.

### Lưu ý khi bảo trì

`UIHostingController` tạo thủ công **không** thừa hưởng environment của SwiftUI, nên trong
`AuroraTabHost.makeUIViewController` phải tự gán `.environmentObject(store)`,
`.environmentObject(connectivity)` và `overrideUserInterfaceStyle = .dark`.

Ngoài ra `CinemoraTabShell` nay nhận `store` qua tham số (`let store: CinemaStore`) thay vì
`@EnvironmentObject`: nếu shell quan sát store thì mỗi lần store publish, cả shell và container
đều bị đánh giá lại.

### Các tối ưu kèm theo trong vòng này

| # | Vấn đề | Cách sửa |
| --- | --- | --- |
| 1 | `CinemaBackground` dùng `GeometryReader` với offset theo tỉ lệ kích thước, và 6 lớp gradient toàn màn hình | Bỏ `GeometryReader`, dùng blob kích thước cố định đặt giữa; còn 4 lớp |
| 2 | `MoviePosterCard`, `MovieShelfCard`, thẻ lịch sử mỗi thẻ 2 lớp shadow (một đen, một màu) | Còn 1 shadow mỗi thẻ, giảm bán kính 16 → 12 |
| 3 | `.scrollPosition(id:)` ở Trang chủ, Thư viện, Tìm kiếm: binding bị ghi lại liên tục khi cuộn, mỗi lần ghi đánh giá lại cả màn hình | Bỏ ở Thư viện/Tìm kiếm (không dùng đến); Trang chủ chuyển sang `ScrollViewReader` với lệnh cuộn lên đầu tường minh |
| 4 | `.onAppear` của shimmer, LivePulse, equalizer, OfflineBanner ghi state mỗi lần view xuất hiện lại | Thêm guard, không ghi lại giá trị đã đúng |
| 5 | `PosterArt` ghi `image = cached` mỗi lần `.task` chạy lại (tức mỗi lần tab hiện ra) | Chỉ ghi khi ảnh thực sự khác |
## 10. Vòng sửa thứ tư: lỗi hiển thị và tìm kiếm tức thì

### 10.1 Lỗi hiển thị: nền gradient làm tràn layout cả màn hình

**Triệu chứng:** sau khi chuyển tab mượt, giao diện Trang chủ vỡ: tiêu đề "CINEMORA" ở
header biến mất, thẻ hero tràn viền không còn bo góc, dòng phim bên dưới bị đẩy lệch sang trái.

**Nguyên nhân:** ở vòng 9, `CinemaBackground` được đổi từ `GeometryReader` sang các blob
kích thước cố định. Nhưng blob được đặt **trực tiếp trong `ZStack`**, và mỗi blob có
`frame(width: diameter, height: diameter)` với `diameter = size * 2.2`, tức blob lớn nhất lên
tới **836pt** — trong khi màn hình chỉ rộng ~390pt.

`ZStack` lấy kích thước bằng kích thước lớn nhất trong các con, nên cả khối nền bị đẩy lên
836pt. Vì nền nằm chung `ZStack` với `ScrollView` của màn hình, `ScrollView` bị đề xuất bề
rộng đó, kéo theo `LazyVStack` rộng ~800pt, header bị căn giữa ra ngoài màn hình và thẻ hero
bị kéo giãn hết cỡ.

**Cách sửa:** đưa toàn bộ blob và vignette vào `.overlay { … }`. `overlay` được định kích
thước bởi view mà nó trang trí và **không bao giờ đẩy kích thước của chính nó trở lại layout**,
nên các blob khổng lồ không còn ảnh hưởng tới bố cục của bất kỳ màn hình nào:

```swift
LinearGradient(colors: [.auroraVoid, .auroraInk, .auroraVoid], startPoint: .top, endPoint: .bottom)
    .overlay { ZStack { /* ba blob + vignette */ } }
    .allowsHitTesting(false)
    .ignoresSafeArea()
```

**Gia cố thêm:** `HeroParallax` cũng được cấp bề rộng xác định bằng
`.containerRelativeFrame(.horizontal) { length, _ in max(length - 40, 0) }`. Trước đó thẻ chỉ
có `.frame(height:)`; khi chỉ ràng buộc chiều cao, bề rộng *lý tưởng* của tiêu đề (một dòng,
cỡ chữ 28) có thể kéo giãn cả `LazyVStack`. `containerRelativeFrame` lấy bề rộng từ
`ScrollView` nên vẫn giữ được `.visualEffect`, không cần `GeometryReader` và không sinh thêm
lượt layout mỗi frame cuộn.

Đã rà lại toàn bộ dự án: không còn phần tử trang trí nào có `frame(width:)` từ 280pt trở lên
nằm trực tiếp trong `ZStack` của màn hình.

### 10.2 Tìm kiếm tức thì (không cần bấm Enter)

**Trước:** phải gõ tên rồi bấm Enter hoặc nút mũi tên mới chạy tìm kiếm.

**Sau:** kết quả tự động hiện theo từng nhịp gõ.

- `TextField` thêm `.onChange(of: keyword) { _, value in scheduleLiveSearch(value) }`.
- `scheduleLiveSearch` **debounce 300ms**: mỗi lần gõ lại huỷ tác vụ đang chờ và hẹn lại, nên
  chỉ có một request cho mỗi cụm từ thay vì một request cho mỗi ký tự.
- Từ 2 ký tự trở lên mới gọi API, đúng như ràng buộc sẵn có của `CinemaStore.search`.
- Xoá hết nội dung ô tìm kiếm thì tự động xoá kết quả.
- Enter và nút mũi tên vẫn hoạt động: chúng **huỷ debounce và tìm ngay**, đồng thời thu bàn phím.

Vì `CinemaStore.search` đã tự bỏ qua các phản hồi đến sai thứ tự (`searchRequestID`), một
request cũ về muộn không thể ghi đè kết quả mới hơn.

Về phần hiển thị, khung xương tải (skeleton) chỉ chiếm màn hình khi **chưa có kết quả nào**.
Khi đang gõ mà đã có kết quả cũ, kết quả cũ được giữ nguyên và chỉ hiện một `ProgressView`
nhỏ cạnh bộ đếm — tránh nhấp nháy toàn màn hình theo từng ký tự.
## 11. Vòng sửa thứ năm: gõ tìm kiếm, vuốt để quay lại, và yêu cầu đăng nhập

### 11.1 Gõ trong ô tìm kiếm bị lag

**Nguyên nhân:** `keyword` là `@State` của `SearchScreen`, nên **mỗi ký tự gõ vào làm cả màn
hình được đánh giá lại**: lọc và sắp xếp lại `filteredResults`, dựng lại ba `Set` cho bộ lọc
(`filterCategories`, `filterCountries`, `filterYears`), dựng lại toàn bộ dãy chip bộ lọc và cả
`LazyVGrid` kết quả. Bàn phím iOS rất nhạy với công việc trên main thread trong lúc gõ, nên
điều đó hiện ra thành độ trễ.

**Cách sửa:** tách ô nhập thành một view riêng `SearchField`, **tự giữ `keyword` của nó**:

- Mỗi ký tự gõ chỉ đánh giá lại `SearchField` — một view nhỏ.
- `SearchScreen` chỉ được thông báo khi người dùng dừng gõ (`onQuery`) hoặc bấm xoá (`onClear`).
- Debounce 300ms chuyển vào bên trong `SearchField`; Enter và nút mũi tên vẫn huỷ debounce và
  tìm ngay.
- Nút "Thử lại" ở trạng thái lỗi nay chạy lại truy vấn hiện tại thay vì gọi hàm cũ.

### 11.2 Vuốt từ mép trái để quay lại

**Nguyên nhân:** mọi màn hình trong app đều gọi `.toolbar(.hidden, for: .navigationBar)`. Khi
thanh điều hướng bị ẩn, UIKit **tắt luôn cử chỉ vuốt-lùi của hệ thống**, nên chỉ còn cách bấm
nút. Trước đây chỉ riêng `MovieDetailScreen` có cử chỉ vuốt riêng, nên các màn hình đẩy khác
(như Tài khoản, Thư viện đã lưu, Tuỳ chọn phụ đề) hoàn toàn không vuốt được.

**Cách sửa:** đưa `NavigationStack` (và `NavigationPath`) vào `AuroraTabScreen` — view gốc của
từng tab — rồi phủ một dải mỏng 22pt ở mép trái:

```swift
.overlay(alignment: .leading) { backSwipeEdge }
```

Dải này chỉ nhận cảm ứng khi `!path.isEmpty` (nên ở tab gốc nó hoàn toàn vô hình với nội dung),
và khi kéo sang phải hơn 55pt theo chiều ngang thì gọi `path.removeLast()` — dùng đúng hiệu ứng
lùi của `NavigationStack`, giống hệt khi bấm nút. Nhờ đặt ở tầng container, **mọi màn hình đẩy
trong cả 5 tab đều vuốt lùi được**.

`MovieDetailScreen` vẫn giữ cử chỉ riêng của nó (cần thiết khi nó được đẩy trong
`fullScreenCover` của trình phát, nơi dải mép trái không với tới). Hai cử chỉ không tranh nhau:
cảm ứng rơi vào dải 0–22pt do dải xử lý, phần 22–36pt do cử chỉ trong màn hình xử lý, và mỗi
lần chạm chỉ một cử chỉ nhận được nên không thể lùi hai bước.

### 11.3 Nút "Trở lại" và thao tác bấm mượt hơn

**Nguyên nhân:** trong `MovieDetailScreen`, tiến độ kéo `edgeBackProgress` là `@State` **của
chính màn hình**. Mỗi frame của thao tác kéo làm `body` của màn hình chi tiết được chạy lại —
tức là dựng lại toàn bộ nội dung nặng (hero, danh sách tập, thẻ đề xuất). Đó chính là cảm giác
"chưa mượt".

**Cách sửa:** chuyển cử chỉ lùi vào một `ViewModifier` nhỏ `EdgeBackDrag`
(`Design/AuroraMotion.swift`) tự giữ tiến độ kéo. `@State` đổi thì chỉ `body` của modifier chạy
lại, còn nội dung màn hình là giá trị đã dựng sẵn nên SwiftUI không dựng lại — thao tác kéo
không còn kéo theo cả màn hình.

Kèm theo: `AuroraTabHostController.viewDidLayoutSubviews` nay chỉ gán lại frame cho những host
có kích thước thật sự thay đổi, thay vì gán lại cả năm host ở mọi lượt layout.

### 11.4 Yêu cầu đăng nhập khi bấm yêu thích

**Trước:** `CinemaStore.toggleFavorite` có `guard accountUser != nil else { return }` — bấm trái
tim khi chưa đăng nhập thì không có gì xảy ra, người dùng không biết vì sao.

**Sau:** nút yêu thích trong `MovieDetailScreen` kiểm tra tài khoản trước, và nếu chưa đăng nhập
thì hiện hộp thoại:

- Tiêu đề: **Cần đăng nhập**
- Nội dung: "Bạn cần đăng nhập để lưu phim vào danh sách yêu thích. Danh sách yêu thích được
  đồng bộ theo tài khoản của bạn."
- Nút **Đăng nhập** mở `AccountSettingsScreen` dạng sheet (màn hình này đã tự hiện biểu mẫu
  đăng nhập khi chưa có tài khoản), nút **Để sau** đóng hộp thoại.

Ràng buộc trong store vẫn được giữ nguyên để bảo vệ ở tầng dữ liệu.
## 12. Vòng sửa thứ sáu: nút "Xem thêm", nguyên nhân gốc của độ trễ, và trình phát

### 12.1 Nút "Xem thêm" mở sai phim

**Nguyên nhân:** trong `HomeScreen.sectionBlock`, nút "Xem thêm" được viết là
`NavigationLink(value: section.movies.first)`. Nó không mở danh sách của mục mà **mở thẳng
trang chi tiết của phim đầu tiên trong mục đó**. Với mục "Phim Mới", phim đầu tiên chính là
phim hero — đúng như hiện tượng bạn gặp: bấm "Xem thêm" ở "Phim Mới" hay "Phim Bộ" đều nhảy
vào *Juliet và Juliet*.

**Cách sửa:** thêm một tuyến điều hướng riêng cho mục:

```swift
struct SectionListRoute: Hashable {
    let kind: String
    let title: String
}
```

`SectionListScreen` hiển thị toàn bộ phim của mục đó trong lưới 2 cột và **tự phân trang khi
cuộn** qua `CinemaAPI.shared.list(page:kind:)`. Nó tự gọi API thay vì dùng
`CinemaStore.catalogMovies`, vì trạng thái đó thuộc tab Thư viện — nếu dùng chung, hai màn
hình sẽ ghi đè danh sách của nhau.

### 12.2 Nguyên nhân gốc của độ trễ nút "Trở lại" (và cảm giác chưa mượt nói chung)

Đây là lỗi quan trọng nhất của vòng này, và nó giải thích đúng hiện tượng "lâu lâu ấn một lần
là được liền, lâu lâu phải ấn liên tục".

**Nguyên nhân:** trạng thái truyền hình nằm chung trong `CinemaStore`, và `TVScreen` mở một kết
nối **server-sent events** chạy mãi. Vì các tab là `UIHostingController` chỉ bị `isHidden`, việc
ẩn một tab **không** kích hoạt `onDisappear` của SwiftUI — nên sau khi bạn ghé tab Truyền hình
một lần, kết nối live vẫn chạy tiếp. Mỗi bản tin SSE (số người xem thay đổi liên tục) ghi vào
`@Published` của store dùng chung, mà `@EnvironmentObject` phát thông báo tới **mọi view đang
quan sát store** — tức là **cả 5 tab cộng mọi màn hình đang mở** đồng loạt dựng lại. Các màn
hình này rất nặng (hero, dải poster, lưới phim), nên main thread bận đúng vào lúc bạn đang
chạm vào nút Trở lại — cú chạm bị xử lý muộn, và cảm giác là "phải ấn lại".

**Cách sửa:** tách hẳn trạng thái truyền hình ra một store riêng `TvStore`
(`State/CinemaStore.swift`), chỉ `TVScreen` quan sát nó:

- `TvStore` giữ `streams`, `videos`, `loading`, `error` cùng hai tác vụ nền.
- `TVScreen` chỉ dùng `@EnvironmentObject private var tv: TvStore`, không còn quan sát
  `CinemaStore` — nên màn hình này cũng không còn dựng lại khi dữ liệu phim thay đổi.
- Bản tin live giờ chỉ làm **một** màn hình dựng lại thay vì toàn app.
- Kết nối vẫn được giữ qua các lần chuyển tab như trước, nên vào tab Truyền hình vẫn tức thì.

Đây là loại lỗi mà việc "đoán" không tìm ra: nó không nằm ở nút bấm, mà ở chỗ một luồng dữ
liệu chạy nền đang âm thầm vô hiệu hoá giao diện của cả ứng dụng.

### 12.3 Chuyển tab mượt hơn

Hai thay đổi trong `AuroraTabHostController`:

1. **Làm nóng trước (`prewarm`)** — sau khi khởi động 1,2 giây, các tab còn lại được tạo lần
   lượt (cách nhau 450ms, vẫn ở trạng thái ẩn). Lần đầu chuyển sang một tab giờ là một cú lật
   hiển thị thay vì một lượt dựng nguội toàn màn hình. Vì `TvStore` đã tách riêng, việc làm
   nóng tab Truyền hình không còn ảnh hưởng tới các tab khác.
2. **Chuyển mờ (cross-fade)** — tab mới hiện lên bằng `UIView.animate` alpha 0 → 1 trong 0,2
   giây, khớp với chuyển động của thanh tab, thay vì cắt phựt. Chỉ đổi alpha: không layout,
   không dựng lại view.

### 12.4 Trình phát mở thẳng ở chế độ ngang

**Trước:** `showPlayer = true` được đặt trước, rồi trình phát mới tự gọi `forceLandscape()`
trong `onAppear` — nên nó hiện ra ở dạng dọc rồi mới xoay.

**Cách sửa:** thêm `OrientationSupport` dùng chung (trước đây mỗi màn hình tự viết một bản
riêng) và hàm `rotateThenPresent`:

```swift
OrientationSupport.rotateThenPresent { showPlayer = true }
```

Nó xoay thiết bị sang ngang trước, chờ 280ms (chính là lúc người dùng thấy màn hình đang xoay),
rồi mới mở trình phát — nên trình phát xuất hiện **đã ở chế độ ngang**. Ba điểm phát phim trong
trang chi tiết (nút "Xem phim", chọn tập, và tự phát khi mở từ phim liên quan) cùng nút "Xem
tiếp" ở màn hình xem tiếp đều dùng chung cách này. `forceLandscape()` trong trình phát vẫn được
giữ để bảo đảm, vì nó vô hại khi đã ở đúng hướng.

### 12.5 Một chi tiết nhỏ

Dải vuốt-lùi ở mép trái được thu từ 22pt xuống 18pt để không phủ lên 2pt đầu của nút "Trở lại"
(các nút này đặt cách mép 20pt), tránh mất vùng chạm một cách không cần thiết.
## 13. Sửa lỗi build IPA (Xcode 26.6)

### 13.1 `HomeScreen.swift:244` — `'error' is immutable`

Trong `SectionListScreen.load`, khối `catch` của Swift **tự sinh một biến tên `error`** trỏ tới
lỗi vừa bắt được. Biến đó che mất thuộc tính `@State private var error` khai báo cùng phạm vi,
nên dòng `error = error.localizedDescription` bị hiểu là đang gán vào giá trị bất biến vừa bắt
được:

```
error = error.localizedDescription
^~~~~  cannot assign to value: 'error' is immutable
```

**Cách sửa:** đổi tên thuộc tính trạng thái thành `loadError` (cả khai báo, chỗ dùng trong
`body`, chỗ reset và trong `catch`). Đây là cái bẫy rất dễ mắc khi đặt tên trạng thái trùng với
tên biến ẩn của `catch`.

### 13.2 `TVScreen.swift:438` — `cannot find 'store' in scope`

Khi tách `TvStore`, tôi đã bỏ `@EnvironmentObject private var store: CinemaStore` khỏi
`TVScreen`. Nhưng màn hình này vẫn cần store ở đúng một chỗ: nó truyền `.environmentObject(store)`
cho `MovieDetailScreen` bên trong `fullScreenCover` của trình phát.

**Cách sửa:** thêm lại store nhưng **dưới dạng thuộc tính thường**, không phải `@EnvironmentObject`:

```swift
struct TVScreen: View {
    /// Giữ, không quan sát. `TVScreen` không được dựng lại mỗi khi store chung
    /// phát thông báo, nên store được truyền vào như một thuộc tính thường.
    let store: CinemaStore
    @EnvironmentObject private var tv: TvStore
```

Và `AuroraTabScreen` truyền vào: `case .tv: TVScreen(store: store)`.

Điểm quan trọng: **`let store` không tạo đăng ký quan sát**. Nếu dùng lại `@EnvironmentObject`,
tab Truyền hình sẽ lại dựng lại mỗi khi dữ liệu phim ở store chung thay đổi — đúng thứ vừa được
gỡ ở vòng trước.

### 13.3 `TVScreen.swift:374` — compiler không suy luận nổi kiểu

```
let snapshot = await Task.detached(priority: .userInitiated) { video.asPlayerMovie }.value
the compiler is unable to type-check this expression in reasonable time
```

Đây là giới hạn của bộ suy luận kiểu Swift với biểu thức `async` lồng trong closure `@MainActor`:
nó phải giải đồng thời kiểu trả về của `Task.detached`, của `.value`, và của phép gán. Dòng này
vốn có từ trước, nhưng thay đổi xung quanh đã đẩy nó vượt ngưỡng.

**Cách sửa:** tách thành hai câu và ghi rõ kiểu:

```swift
let source = video
let snapshot: Movie = await Task.detached(priority: .userInitiated) {
    source.asPlayerMovie
}.value
```

### 13.4 Phòng ngừa thêm

- `OrientationSupport.rotateThenPresent` được viết lại bằng `DispatchQueue.main.asyncAfter`
  thay cho `Task { @MainActor in … }`, để hàm không mang yêu cầu cô lập actor — mọi chỗ gọi
  đều đơn giản và không phụ thuộc ngữ cảnh.
- Đã rà lại toàn bộ dự án: chỉ có đúng một chỗ mắc lỗi che tên `error` (13.1), các chỗ còn lại
  dùng `self.error` nên không bị ảnh hưởng.
## 14. Vòng 8 — "Aurora Lite": nhẹ hơn, mượt hơn, và quan sát theo từng thuộc tính

Ba việc, xếp theo mức ảnh hưởng thực tế.

### 14.1 Chuyển store sang `@Observable` (ảnh hưởng lớn nhất)

Trước đây `CinemaStore` là `ObservableObject` với 34 thuộc tính `@Published`, và mọi màn hình đọc
nó qua `@EnvironmentObject`. Cơ chế đó **không biết màn hình nào đọc thuộc tính nào**: chỉ cần
*một* thuộc tính đổi (ví dụ `homeMovies`), SwiftUI đánh dấu **mọi** view đang giữ store là cần
dựng lại — cả 5 tab cộng mọi màn hình đã mở, kể cả những màn hình đang ẩn và không hề dùng dữ
liệu đó. Với các màn hình nặng như Trang chủ hay Thư viện, mỗi lần cập nhật dữ liệu là một lượt
dựng lại toàn bộ cây giao diện.

Bản này chuyển `CinemaStore`, `TvStore` và `ConnectivityMonitor` sang `@Observable` (Observation
framework, iOS 17):

- Bỏ toàn bộ `@Published` — `@Observable` tự theo dõi.
- `@EnvironmentObject private var store` → `@Environment(CinemaStore.self) private var store`.
- `.environmentObject(store)` → `.environment(store)`.

Khác biệt cốt lõi: `@Observable` ghi nhận **chính xác thuộc tính nào được đọc trong `body`**. Một
bản tin truyền hình, một cập nhật yêu thích hay một trang phim mới giờ chỉ dựng lại **đúng màn
hình dùng dữ liệu đó**. Đây là lý do gốc khiến app "đẹp nhưng nặng".

Lưu ý kỹ thuật: `@Environment(CinemaStore.self)` **crash nếu thiếu** thay vì trả về nil, nên mọi
đường dẫn trình bày (root, từng tab, và mọi `sheet`/`fullScreenCover`) đều được kiểm tra là có
`.environment(store)`. Các chỗ tái chèn trong sheet/cover vẫn giữ nguyên.

### 14.2 Ngôn ngữ giao diện "Aurora Lite"

`AuroraSurface` (nền của mọi card) trước đây xếp chồng **ba lớp**: gradient 3 điểm dừng, viền
gradient, và một bóng đổ đen `radius 14`. Mỗi bóng đổ là một lượt vẽ ngoài màn hình, và khi có
vài chục card cùng lúc, compositor phải làm việc đó **mỗi khung hình khi cuộn**.

Aurora Lite giữ nguyên vẻ ngoài nhưng chỉ còn **một nền gradient + một viền mảnh 0.8pt**, không
bóng đổ. Chỉ những bề mặt "hero" (thẻ đăng nhập, hero card) khai báo `glow` mới còn một bóng mờ
nhẹ. `auroraHalo` cũng được thu bán kính xuống tối đa 10pt.

Bỏ luôn `.blur(radius: 6)` trong trạng thái rỗng và animation "thở" chạy vô hạn của nó.

### 14.3 Chính sách animation

Nguyên tắc: **không có animation nào chạy vô hạn trong phần giao diện thường trực.** Một
`repeatForever` duy nhất cũng đủ giữ vòng lặp vẽ ở tần số tối đa liên tục, khiến toàn bộ app —
kể cả chuyển tab — luôn nặng.

- Bỏ `repeatForever` ở banner mất kết nối và ở chấm trạng thái thiết bị.
- `LivePulse` mặc định **không** chạy ripple; chỉ đúng một chỉ báo "đang phát" trên tab Truyền
  hình còn ripple. Lưới kênh dùng chấm tĩnh.
- `AuroraReveal` chỉ chạy hiệu ứng cho **7 thẻ đầu tiên**. Thẻ sinh ra sau đó — khi cuộn lưới
  dài — hiện ra tức thì, nên cuộn không phải chạy animation cho cả hàng poster.
- Animation còn lại đều là loại rẻ (transform/opacity) và nằm ở màn hình riêng: trình phát,
  màn hình xem tiếp, QR, màn hình khởi động.

### 14.4 Về tốc độ build

Thời gian build thực tế trên Codemagic chỉ khoảng 1 phút — phần lớn thời gian trước đây bị mất
vào những lần build **thất bại**. Ba lỗi biên dịch đã sửa ở mục 13 (một lỗi trong đó là compiler
từ chối suy luận kiểu, kiểu lỗi này rất tốn thời gian biên dịch). Giao diện nhẹ hơn cũng giúp
bớt các biểu thức modifier lồng nhau. Ngoài ra `project.yml` đã bật
`COMPILER_INDEX_STORE_ENABLE=NO` sẵn.

## 15. Sửa lỗi build sau khi chuyển sang `@Observable`

Hai lỗi duy nhất:

```
CinemaStore.swift:566:9: main actor-isolated property 'eventsTask' can not be referenced from a nonisolated context
CinemaStore.swift:567:9: main actor-isolated property 'videoRefreshTask' can not be referenced from a nonisolated context
```

**Nguyên nhân.** Macro `@Observable` không giữ thuộc tính `var` ở dạng stored — nó sinh ra một cặp
computed property (get/set) có theo dõi quan sát. Getter là một member thuộc actor, mà `deinit`
lại là ngữ cảnh **nonisolated**, nên đọc thuộc tính từ `deinit` trở thành lỗi. Trước khi chuyển
sang `@Observable`, hai thuộc tính này là stored nên `deinit` đọc được bình thường.

Bằng chứng cho thấy đúng là như vậy: trong log chỉ có hai lỗi, và cả hai đều là `var`. Thuộc tính
`let` (như `monitor` trong `ConnectivityMonitor`) không bị macro đụng tới, nên `deinit` của nó
vẫn hợp lệ — compiler không báo gì.

**Cách sửa.** Đánh dấu `@ObservationIgnored` cho toàn bộ thuộc tính sổ sách nội bộ:

- `eventsTask`, `videoRefreshTask`, `detailTask`, `catalogTask`
- `homePage`, `detailRequestID`, `catalogRequestID`, `searchRequestID`
- `nextAuthAttemptAt`, `lastHomeRefreshAt`

Tất cả đều là `private`, nên không view nào có thể quan sát chúng; đưa ra ngoài cơ chế quan sát
vừa đúng về ngữ nghĩa, vừa tránh overhead theo dõi vô ích, vừa giữ chúng là stored property để
`deinit` hợp lệ.

**Ghi chú cho lần bảo trì sau:** trong một lớp `@Observable`, mọi `var` đều trở thành computed.
Nếu cần đọc/ghi một thuộc tính từ `deinit` hay từ ngữ cảnh nonisolated, hãy đánh dấu nó
`@ObservationIgnored`.

## 16. Sửa lỗi crash khi đang dùng app

**Triệu chứng:** dùng app một lúc thì bị văng ra ngoài, không có quy luật rõ ràng.

**Thủ phạm:** dòng hack KVC để ép xoay màn hình, xuất hiện ở **3 chỗ**:

```swift
UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
```

- `CinemoraApp.swift` trong `OrientationSupport.rotate`
- `CinemaPlayerScreen.swift` khi bật/tắt toàn màn hình
- `Views/TVScreen.swift` khi bật/tắt toàn màn hình

Đây là cách ép xoay "truyền miệng" từ nhiều năm trước. Apple đã chuyển thuộc tính
`orientation` ra khỏi `UIDevice`, nên từ iOS 16 trở đi lệnh này là **hành vi không xác định**: nó
có thể chạy êm nhiều lần rồi bất ngờ ném ngoại lệ. Vì nó nằm trên đường mở/đóng trình phát — tức
mỗi lần bạn bấm xem phim hoặc thoát toàn màn hình — app sẽ "sống một lúc rồi chết", đúng như mô
tả. Đây cũng là kiểu lỗi rất khó tái hiện vì phụ thuộc thời điểm.

**Cách sửa:** bỏ cả ba dòng. Việc ép xoay vẫn hoạt động đầy đủ nhờ hai API chính thức đã có sẵn
trong code:

1. `CinemoraAppDelegate.orientationLock` trả về từ
   `application(_:supportedInterfaceOrientationsFor:)` — quy định tập hướng được phép.
2. `windowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))` kèm
   `setNeedsUpdateOfSupportedInterfaceOrientations()` — yêu cầu hệ thống xoay ngay.

Trên iOS 16+, hack KVC vốn đã không còn tác dụng, nên bỏ nó không mất gì.

### 16.1 Thêm phòng ngừa áp lực bộ nhớ

`PosterMemoryGuard` lắng nghe `UIApplication.didReceiveMemoryWarningNotification` và xoá cache
ảnh đã giải mã. Trước đây không có gì tự giải phóng ảnh: một phiên duyệt phim dài chạm tới hàng
trăm poster, bộ nhớ chỉ tăng chứ không giảm. Đồng thời hạ `totalCostLimit` của cache từ 48MB
xuống 32MB. Đây là biện pháp phòng ngừa cho kiểu văng app do hệ thống thu hồi bộ nhớ — khác với
nguyên nhân chính ở trên.

## 17. Crash khi thoát khỏi trình phát

**Triệu chứng:** bấm vào một phim để xem, vào trình phát bình thường, nhưng bấm "Trở lại" để về
màn hình app thì app văng.

**Đường đi của lỗi.** Trình phát đóng lại thì `onDisappear` chạy hai việc:

```swift
.onDisappear {
    if scenePhase == .active { playback.shutdown() }
    forcePortrait()          // <-- chỗ này
}
```

`forcePortrait()` gọi `forceOrientation(.portrait)`, mà hàm đó trước đây có dòng hack KVC
`UIDevice.current.setValue(_:forKey:"orientation")`. Vậy đây **cùng một nguyên nhân với mục 16**,
chỉ khác là điểm rơi: không phải "sau vài lần dùng" mà là ngay lần bấm trở lại đầu tiên, vì đường
thoát luôn chạy qua đây. Bỏ dòng hack là hết.

### 17.1 Vá thêm một điểm dọn dẹp của trình phát

Hai lớp điều khiển trình phát lệch nhau ở `deinit`:

- `TVPlaybackController` (tab Truyền hình) — dọn cả notification **và** time observer.
- `PlaybackController` (trình phát phim) — chỉ dọn notification, **quên time observer**.

`shutdown()` có gỡ time observer, nhưng cover có thể bị tháo mà `shutdown()` không chạy. Để lại
một periodic observer đã đăng ký trên một `AVPlayer` sống lâu hơn bộ điều khiển là dạng lỗi chỉ
nổ khi màn hình đang bị đóng. Nay `deinit` của trình phát gỡ nốt, giống hệt bản TV.

### 17.2 Kết quả rà soát các điểm crash còn lại

| Điểm | Trạng thái |
| --- | --- |
| Hack KVC xoay màn hình (3 chỗ) | đã bỏ |
| Time observer của trình phát | đã gỡ trong `deinit` |
| PiP: `stopPictureInPicture` | đã có guard `isPictureInPictureActive` |
| Audio session | mọi lệnh đều `try?`, không deactivate sai chỗ |
| Camera (simulator / máy không camera) | có guard, báo lỗi thay vì văng |
| `force unwrap` còn lại | 3 × `URLComponents(url: baseURL)!` (baseURL hợp lệ), 2 × `layer as! AVPlayerLayer` (layer do chính lớp đó khai báo) |
| Ghi store trong `body` | không có (không tạo vòng lặp cập nhật) |
| Chèn store cho `@Observable` | đã phủ hết root, 5 tab, mọi sheet/cover |
| Cache ảnh | có trần, có xử lý cảnh báo bộ nhớ |

Điểm chưa chạm, chỉ nên xử lý nếu build này vẫn văng: `canStartPictureInPictureAutomaticallyFromInline = true`
trong `PictureInPictureCoordinator` — tự động vào PiP khi video đang chiếu inline, có thể va chạm
với lúc `AVPlayerLayer` bị tháo.

## 18. Đăng xuất tất cả thiết bị và độ mượt khi thoát trình phát

### 18.1 Thiết bị khác nhận lệnh đăng xuất quá chậm

**Triệu chứng:** thiết bị bấm "Đăng xuất tất cả thiết bị" thì thoát ngay, còn các thiết bị khác
phải khá lâu mới bị đăng xuất.

**Nguyên nhân.** Thiết bị bấm nút thoát ngay vì `logoutAllDevices()` xoá phiên **cục bộ trước**, rồi
mới gọi API. Các thiết bị khác không ai báo cho chúng — chúng chỉ biết khi tự hỏi máy chủ, mà vòng
hỏi đó chạy **mỗi 20 giây** (`AccountSessionWatcher`). Vì vậy thời gian chờ tệ nhất là 20 giây.

Con số 20 giây đó là do tôi đặt dè dặt ở vòng trước: hồi đó mỗi lần store đổi trạng thái là mọi tab
vẽ lại, nên hỏi dày sẽ tốn. Nay store đã chuyển sang `@Observable` và `checkAccountSession()` chỉ
phát tín hiệu khi người dùng **thật sự** thay đổi, nên hỏi dày gần như không tốn gì trên màn hình.

**Cách sửa.**

1. Giảm chu kỳ hỏi từ **20 giây xuống 5 giây** — một request nhỏ, và các lần hỏi không có gì mới
   thì không gây vẽ lại.
2. Thêm kiểm tra **ngay khi app trở lại tiền cảnh**: đây chính là lúc người dùng cầm thiết bị kia
   lên và nhận ra mình đã bị đăng xuất, nên không cần chờ đến nhịp tiếp theo.

### 18.2 Thoát trình phát bị khựng

**Triệu chứng:** đang trong trình phát, bấm trở ra thấy hơi lag.

**Nguyên nhân.** `onDisappear` chạy `playback.shutdown()` ngay **trong lúc animation đóng màn hình
đang chạy**. Hàm này làm những việc nặng và đồng bộ trên main thread: nhả `AVPlayerItem`, gỡ
observer, tắt audio session, ghi lại vị trí xem dở. Chừng đó đủ để chặn main thread vài chục
mili-giây — đúng khoảng thời gian animation cần để mượt, nên mắt thấy khựng.

**Cách sửa.** Tách làm hai nhịp:

- **Ngay lập tức** (rẻ, cần phản hồi tức thì): `pauseForDismissal()` chỉ tạm dừng hình/tiếng, cùng
  `forcePortrait()` để bắt đầu xoay về dọc.
- **Sau khi animation đóng xong (350ms)**: ghi vị trí xem dở rồi mới `shutdown()`.

Đã áp dụng cho cả 4 chỗ: trình phát phim, trình phát toàn màn hình của tab Truyền hình, trình phát
video toàn màn hình, và lúc rời tab Truyền hình. Riêng `openRelatedMovie` vẫn dừng ngay vì ở đó
cần tắt tiếng trước khi mở trình phát mới.

## 19. Thanh menu che mất form khi bàn phím hiện lên

**Triệu chứng:** vào màn hình cần điền (đăng nhập, tìm kiếm, yêu cầu phim…), bàn phím hiện lên và
thanh menu dưới cùng bị đẩy lên nằm chồng lên form — hàng cuối của form như nút "Đăng nhập" hay
liên kết "Quên mật khẩu" bị che, nhìn rất chật.

**Nguyên nhân.** Thanh menu được gắn bằng `.overlay(alignment: .bottom)`, tức nó **nổi trên** nội
dung chứ không tham gia vào vùng an toàn. Khi bàn phím mở, iOS đẩy thanh này lên ngang tầm bàn
phím, và vì nó là lớp phủ nên nội dung form ở dưới bị nó che mất, không cách nào cuộn qua được.

**Cách sửa.** Cho thanh menu **tự né khi đang gõ**:

- Có bàn phím: thanh trượt xuống 140pt, mờ dần và ngừng nhận chạm — dùng đúng lò xo `Motion.sheet`
  như phần còn lại của app.
- Bàn phím tắt: thanh trượt về chỗ cũ ngay lập tức.

Điểm quan trọng: **thanh menu không bị loại bỏ**, nó chỉ tạm lùi ra trong lúc gõ. Vì nó là lớp phủ
nên khi lùi đi, bố cục phía dưới **không xê dịch** — không có giật, không có nhảy layout, form
được trả lại trọn vẹn chiều cao.

Kết hợp sẵn có: ba màn hình đã dùng `.scrollDismissesKeyboard(.interactively)`, nên chỉ cần kéo
nhẹ form xuống là bàn phím đóng và thanh menu trượt trở lại — thao tác rất tự nhiên.

Nếu muốn thanh menu **vẫn hiện** trong lúc gõ, chỉ cần đổi phương án: thay vì trượt đi, cho nó thu
gọn lại thành dạng chỉ có icon (bỏ nhãn chữ, thấp hơn khoảng 20pt). Nói một câu là tôi đổi.

## 20. Thanh cuộn và cách ẩn bàn phím

### 20.1 Bỏ thanh cuộn

Thanh cuộn dọc bên phải xuất hiện mỗi lần lướt, trông không hợp với giao diện. Đã thêm
`.scrollIndicators(.hidden)` cho **tất cả** vùng cuộn dọc: Trang chủ (kể cả danh sách "xem thêm"),
Thư viện, Lưu (4 màn hình), Tìm kiếm, Yêu cầu phim, Tài khoản, Đổi mật khẩu, Tùy chỉnh phụ đề,
Truyền hình, và 3 vùng cuộn trong trình phát. Danh sách tập phim trong trình phát đổi từ
`showsIndicators: true` sang `false`.

Các dải cuộn ngang (shelf poster) vốn đã tắt sẵn. Việc ẩn thanh cuộn **không ảnh hưởng** thao tác
lướt — vẫn kéo lên xuống bình thường, chỉ là không còn thanh chỉ báo.

### 20.2 Chạm ra ngoài để ẩn bàn phím, chạm vào ô nhập để hiện lại

Thêm hai tiện ích dùng chung trong `Design/CinemaComponents.swift`:

- `UIApplication.auroraEndEditing()` — thu hồi first responder, tức đóng bàn phím.
- `View.auroraDismissKeyboardOnTap()` — đặt một lớp cảm ứng **phía sau** nội dung.

Điểm mấu chốt là lớp cảm ứng nằm sau: chạm vào ô nhập thì ô nhập vẫn nhận được và bàn phím hiện
lên; chạm vào nút thì nút vẫn hoạt động; chỉ những cú chạm vào khoảng trống hoặc chữ thường mới
rơi xuống lớp này và đóng bàn phím. Nhờ vậy không có chuyện vừa chạm vào ô nhập đã bị đóng bàn
phím — lỗi hay gặp khi gắn cử chỉ chạm lên toàn màn hình.

Đã áp dụng cho 4 màn hình có ô nhập: Đăng nhập/Đăng ký, Đổi mật khẩu, Tìm kiếm, Yêu cầu phim.
Muốn hiện lại bàn phím thì chỉ cần chạm vào ô nhập.

## 21. Sửa lại cách ẩn bàn phím (bản 20.2 chưa chạy)

**Triệu chứng:** chạm ra ngoài ô nhập nhưng bàn phím không đóng.

**Vì sao bản trước thất bại.** Tôi đặt lớp cảm ứng **phía sau** nội dung. Cách đó không thể chạy
với `ScrollView`: scroll view chiếm trọn khung của nó khi kiểm tra điểm chạm, nên cú chạm vào khoảng
trống **không bao giờ** rơi xuống lớp nằm sau nó. Lớp đó tồn tại nhưng vô hình với mọi cú chạm.

**Cách làm mới — bộ nhận diện chạm ở tầng cửa sổ.** `AuroraKeyboardDismissLayer` gắn một
`UITapGestureRecognizer` lên window, nên nó thấy **mọi** cú chạm trong app:

- Chạm vào ô nhập → bỏ qua, bàn phím giữ nguyên (đúng yêu cầu: chạm vào ô nhập để hiện lại bàn phím).
- Chạm vào bất kì chỗ nào khác — khoảng trống, chữ tiêu đề, thẻ phim, thanh menu, nút trở lại, nền
  sheet — → đóng bàn phím.
- **Lướt lên xuống không đóng bàn phím**, vì đây là bộ nhận diện *chạm*, không phải *kéo*. Đúng
  yêu cầu.

Hai thiết lập giữ cho phần còn lại của app không bị ảnh hưởng: `cancelsTouchesInView = false` để
nút bấm vẫn nhận được cú chạm, và cho phép nhận diện đồng thời để thao tác cuộn, chuyển tab, các
cử chỉ riêng của trình phát vẫn chạy như cũ.

Việc gắn vào window do `didMoveToWindow` đảm nhiệm: `updateUIView` có thể chạy trước khi view nằm
trong window, nên nếu chỉ dựa vào nó thì có lúc bộ nhận diện không bao giờ được gắn.

**Sửa kèm:** ba màn hình đang bật `.scrollDismissesKeyboard(.interactively)` — tức kéo là đóng bàn
phím, trái với yêu cầu mới. Đã đổi thành `.never`: chỉ chạm ra ngoài mới đóng.

## 22. Văng app khi trở ra từ trình phát (truy đúng nguyên nhân)

**Triệu chứng:** xem phim → trở ra trang chi tiết phim → trở ra màn hình app thì bị văng.

**Nguyên nhân chính xác — do bản vá ở mục 18.2 của tôi.** Để thoát trình phát mượt, tôi dời phần
dọn dẹp nặng vào một `Task` chạy sau 350ms. Nhưng trong đó tôi gọi `saveLocalWatchProgress()`, mà
hàm này đọc `@Environment(CinemaStore.self) private var store`. Sau khi view trình phát đã bị tháo
khỏi cây giao diện, **environment không còn được cài đặt nữa** — đọc nó lúc đó làm SwiftUI trap và
app biến mất ngay lập tức. Vì độ trễ đúng 350ms nên hiện tượng trông như do cú bấm trở ra ở trang
chi tiết gây ra, trong khi thủ phạm là bước dọn dẹp của trình phát.

**Cách sửa:** đọc và giữ lại mọi thứ cần dùng **trước khi** hoãn — `store`, `movie`, `episode`,
tên server, `playback` — rồi phần chạy sau chỉ làm việc trên các tham chiếu đã giữ, không chạm vào
view nữa. Cùng lỗi này cũng có ở chỗ lưu tùy chọn phụ đề trong trình phát (`DispatchQueue.main.async`
đọc `store`); đã sửa tương tự.

**Ba chỗ văng khác tìm được khi rà toàn app:**

1. `Views/MovieDetailScreen.swift` — `availableServers[playableServerIndex].episodes[0]` không kiểm
   tra: chỉ số server cũ, hoặc server không có tập nào, là văng. Đã thêm `guard` + dùng `.first`.
2. `Player/CinemaPlayerScreen.swift` — `visibleSettingsTabs[0]` không kiểm tra: nếu danh sách rỗng
   là văng. Đã đổi sang `.first`.
3. Không còn `try!`, `as!`, `fatalError` nào trong toàn bộ mã. Hai chỗ `as! AVPlayerLayer` là an
   toàn theo thiết kế vì lớp `UIView` đó đã khai báo `layerClass` là `AVPlayerLayer`.

Đã rà thêm: mọi `deinit`, mọi `onDisappear`, mọi chỉ số mảng theo biến, và mọi closure chạy trễ
trong app. Chỉ còn lại đúng mẫu đã sửa ở trên.

## 23. Màn hình đen khi bấm video liên quan, và siết lại đường thoát trình phát

### 23.1 Nguyên nhân màn hình đen

`openRelatedMovie()` gọi `playback.shutdown()` — hàm này gỡ luôn item khỏi player — **trước khi**
phim liên quan kịp hiện ra. Nhưng player không hề bị đóng ở bước đó: `MovieDetailScreen` **đổi nội
dung của chính cover đang mở** sang phim B (xem nhánh `if let relatedMovieRoute`), nên bề mặt
player A vẫn nằm trên màn hình, chỉ là đã bị gỡ item → đen.

Hai lỗi phụ cùng nằm trên đường này:

- `forcePortrait()` trong `onDisappear` chạy ngay lúc bàn giao, ép app về dọc trong khi player B
  sắp mở ở ngang, gây xoay hai lần và thêm một nhịp đen.
- `onDisappear` có thể được gọi hơn một lần cho một cover, khiến phần dọn dẹp chạy hai lần.

**Cách sửa:** chỉ `pauseForDismissal()` (giữ nguyên khung hình cuối) rồi bàn giao; việc gỡ item để
cho `onDisappear` làm sau. Thêm cờ `handingOffToRelated` để **giữ nguyên hướng ngang** qua lúc bàn
giao, và cờ `didScheduleTeardown` để phần dọn dẹp chỉ chạy đúng một lần.

### 23.2 Vá thêm một chỗ cùng loại lỗi văng

`Views/SubtitlePreferencesScreen.swift` cũng đọc `store` bên trong `DispatchQueue.main.async` mà
không giữ bản sao cục bộ — đúng mẫu đã làm văng app ở mục 22. Đã sửa.

## 24. Giao diện mới: "Studio" — phẳng, một màu nhấn, bớt hiệu ứng

Yêu cầu: bớt hiệu ứng nhưng vẫn phải đẹp. Tôi tra cứu lại hướng thiết kế dark mode hiện hành
(nguyên tắc chung: **dùng độ cao của bề mặt để tạo chiều sâu, không dùng đổ bóng; dùng màu nhấn
thật tiết chế**) rồi thay hệ thống thiết kế, chứ không sửa từng màn hình — mọi màn hình đều lấy
màu, chữ, thẻ từ `CinemoraStyle.swift`, nên đổi ở đó là đổi toàn app.

**Bảng màu.** Nền gần đen và **trung tính** (#08080A → #0E0E11) để poster phim là thứ duy nhất có
màu trên màn hình — trang trí nhiều màu sẽ tranh chấp với ảnh phim và làm thư viện trông ồn. Chỉ
còn **một màu nhấn: vàng ấm (#EFB75A)**, dùng cho hành động chính, tab đang chọn và gạch đầu mục.
Các tông còn lại chỉ mang nghĩa: mint = đang phát, cam = cảnh báo, xám = phụ.

**Chữ.** Bỏ font rounded, chuyển sang SF với độ đậm và tracking chặt hơn. Tiêu đề dựa vào trọng
lượng chứ không vào hình dáng chữ, nên đọc ra chất biên tập thay vì "đồ chơi".

**Bề mặt.** Thẻ giờ là **một nền phẳng + viền 1pt** thay vì gradient ba lớp + viền gradient + đổ
bóng. Chiều sâu đến từ việc nền thẻ sáng hơn nền app — đúng cách làm elevation của dark mode.

**Nền app.** Bỏ ba khối sáng 800pt và lớp vignette, thay bằng một dải sáng nhạt duy nhất ở đỉnh.

**Những gì đã gỡ:**

| Hiệu ứng | Trước | Sau |
| --- | --- | --- |
| `blur()` | 2 | 0 |
| Material / kính mờ | nhiều | 0 |
| Đổ bóng trang trí trong màn hình app | 18 | 0 |
| Hiệu ứng cuộn theo vị trí (`scrollTransition`) | có | 0 |
| Icon nhún / nhấp nháy (`symbolEffect` trang trí) | 3 | 0 |
| Quầng sáng (`auroraHalo`) | mọi hero + nút chính | không vẽ gì |
| Chữ gradient | tiêu đề | chữ trắng đặc |
| Tab bar | viên gradient + quầng | viên phẳng màu nhấn |

Giữ lại có chủ đích: các vòng xoay chờ (tải dữ liệu, quét QR) và đổ bóng trên chrome trình phát —
đó là thông tin chức năng trên nền video, không phải trang trí.

## 25. Tìm kiếm, Picture-in-Picture và trạng thái cuối phim

### 25.1 Vì sao bàn phím gõ bị lag

`filteredResults` được tính lại **mỗi lần store phát thông báo** — mà khi đang gõ, mỗi nhịp
debounce lại có một kết quả mới về. Trong hàm sắp xếp, `dateValue()` **tạo mới hai
`ISO8601DateFormatter` cho mỗi lần so sánh**, nên một lần sắp xếp vài trăm phim sinh ra hàng trăm
đối tượng formatter. Toàn bộ việc đó chạy trên main thread, đúng lúc bàn phím đang cần nó.

**Sửa:** hai formatter nay là `static let` (tạo một lần cho cả vòng đời app), không còn cấp phát
trong vòng lặp so sánh.

### 25.2 Vì sao ấn vào phim trong kết quả tìm kiếm bị văng

Lưới kết quả có `.id("search-results-\(submitted)")` — mỗi lần có kết quả của truy vấn mới là
SwiftUI **tháo và dựng lại toàn bộ lưới**. Nếu lúc đó người dùng vừa ấn vào một phim và màn hình
chi tiết đang được đẩy lên, view đang giữ việc điều hướng bị huỷ ngay dưới chân nó → văng app.
Vào lại thì bình thường vì lúc đó không còn kết quả nào đang bay về nữa.

**Sửa:** bỏ `.id(...)` trên lưới — danh tính từng thẻ vốn đã ổn định qua `ForEach(id: \.element.id)`.

### 25.3 Picture-in-Picture

Ba lỗi riêng biệt:

1. **Trình phát web chưa bao giờ bật `allowsPictureInPictureMediaPlayback`.** Với các nguồn phát
   trong `WKWebView`, cờ này là điều kiện bắt buộc — thiếu nó thì PiP không thể xảy ra, dù nút có
   hiện. Đã bật.
2. **Nút PiP thường không làm gì.** `isPictureInPicturePossible` chỉ chuyển sang `true` sau khi
   player layer đã vẽ khung hình đầu tiên, thường là sau khi người dùng đã bấm nút. Bản cũ thử lại
   đúng một lần sau 280ms rồi im lặng bỏ cuộc. Nay theo dõi thuộc tính này bằng KVO và khởi động
   PiP ngay khi được phép.
3. **Cài đặt PiP chỉ để ẩn/hiện nút, không điều khiển hành vi.** `canStartPictureInPictureAutomaticallyFromInline`
   bị đặt cứng là `true`. Nay nó lấy từ chính cài đặt `playbackDefaults.pictureInPicture`, nên khi
   bật, iOS được phép tự đưa hình sang PiP lúc app rời tiền cảnh.

Kèm theo: `stop()` huỷ luôn yêu cầu đang chờ, và các callback `didStart` / `failedToStart` nay cập
nhật `isActive` để nút không kẹt trạng thái.

### 25.4 Hết phim / hết tập cuối

Trình phát phim **không hề lắng nghe `AVPlayerItemDidPlayToEndTime`**. Trạng thái `isPlaying` chỉ
được cập nhật bởi periodic time observer, mà observer này ngừng bắn ngay khi phim kết thúc — nên
trạng thái cuối cùng đọng lại là "đang phát" và icon pause không bao giờ trở về.

**Sửa:** lắng nghe thông báo kết thúc → dừng phát, đặt `didReachEnd`, đưa icon về nút phát lại
(`arrow.counterclockwise`); bấm nút đó sẽ phát lại từ đầu. Chuyển tập hoặc tua lại thì cờ được xoá.

## 26. Văng app khi mở phim rồi trở ra (nguyên nhân gốc)

Đây là lỗi nghiêm trọng nhất trong loạt lỗi "lâu lâu ấn không ăn" và "văng khi trở ra".

`AuroraKeyboardDismissLayer` gắn một `UITapGestureRecognizer` lên **window** để ấn ra ngoài ô nhập
thì đóng bàn phím. Nhưng **`UIGestureRecognizer` không giữ target của nó** — target là tham chiếu
không sở hữu. Coordinator của lớp này do `makeCoordinator()` tạo ra, tức là **chỉ sống theo màn hình
đã tạo nó**. Khi màn hình đó bị tháo (đẩy màn hình phim lên, rồi trở ra), coordinator bị giải phóng,
**nhưng recognizer vẫn nằm trên window**. Cú chạm tiếp theo gửi `handleTap(_:)` tới một đối tượng đã
bị huỷ → `EXC_BAD_ACCESS` → văng app.

Vì sao đúng kịch bản bạn gặp: lần chạm đầu tiên còn an toàn vì coordinator còn sống; sau khi vào
phim rồi trở ra, nó đã chết; chạm vào phim tiếp theo là cú chạm giết app.

Điều này cũng giải thích các triệu chứng trước đây: nút "Trở lại" có lúc phải ấn nhiều lần mới ăn —
một số cú chạm rơi vào đối tượng đã huỷ nên bị nuốt mất, chỉ khác nhau ở việc lần này có nổ hay không.

**Sửa:** target của recognizer nay là **một singleton sống suốt vòng đời app**
(`@MainActor static let shared`), nên không còn khả năng gửi thông điệp tới đối tượng đã huỷ. Kèm
theo, khi window đổi thì recognizer cũ được gỡ trước khi gắn cái mới, tránh chồng nhiều recognizer.

## 27. Văng khi trở ra từ chi tiết phim rồi lướt tiếp

### Nguyên nhân 1 — chỉ số vượt mảng (đúng kịch bản bạn gặp)

Sáu vòng lặp trong app dùng **chỉ số làm danh tính** cho `ForEach`:

```swift
ForEach(servers.indices, id: \.self) { index in
    let server = servers[index]      // ← có thể vượt mảng
```

`servers` và `episodes` ở màn hình chi tiết không phải mảng cố định — chúng suy ra từ `movie`:

```swift
private var servers: [MovieServer] { movie?.availableServers ?? [] }
private var episodes: [MovieEpisode] { servers.indices.contains(selectedServer) ? servers[selectedServer].episodes : [] }
```

Mỗi lần màn hình chi tiết tải lại dữ liệu, `movie` bị thay bằng bản mới (hoặc về `nil` khi màn hình
bị tháo trong lúc trở ra). Số nguồn/số tập có thể **giảm**, nhưng `ForEach` theo chỉ số vẫn còn hàng
ở vị trí cũ và SwiftUI vẫn hỏi lại hàng đó một lần nữa trong lúc cập nhật. Lúc đó `servers[index]`
truy cập ngoài mảng → **trap "Index out of range" → văng app**. Lần vào đầu thường an toàn vì dữ
liệu vừa tải và chưa bị thay; các lần sau mới nổ — đúng như bạn mô tả.

**Sửa:** cả sáu chỗ chuyển sang ảnh chụp liệt kê kèm danh tính theo phần tử, và **không truy cập
bằng chỉ số nữa**:

```swift
ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
    serverChip(server, selected: selectedServer == index) { … }
```

Các vị trí: màn hình chi tiết (2), trình phát phim (3), trình phát truyền hình (1).

### Nguyên nhân 2 — recognizer bàn phím nhắm vào đối tượng đã huỷ

Xem mục 26. `AuroraKeyboardDismissLayer` gắn `UITapGestureRecognizer` lên window, mà
`UIGestureRecognizer` **không giữ target**. Nay target là singleton sống suốt vòng đời app.
## 28. Tính năng bình luận cho từng phim

Thêm khối bình luận vào trang chi tiết phim, dành cho thành viên đã đăng nhập.

### Thành phần mới

| Tệp | Vai trò |
| --- | --- |
| `Models/CommentModels.swift` | `MovieComment`, `MovieCommentThread`, `CommentAuthor` + giải mã dễ tính (`FlexibleID`, `FlexibleDate`) |
| `State/CommentsStore.swift` | Tải, gửi lạc quan, làm mới định kỳ, trả lời, xoá, kho lưu tạm trên thiết bị |
| `Views/CommentsSection.swift` | Ô soạn + danh sách bình luận + huy hiệu quản trị |
| `API/CinemaAPI.swift` | `cinema.comments`, `cinema.addComment`, `cinema.deleteComment` |
| `COMMENTS-BACKEND.md` | Hợp đồng API để backend bổ sung ba procedure |

### Hành vi

- **Chỉ thành viên đã đăng nhập** mới thấy ô soạn; khách thấy lời mời đăng nhập và dùng
  lại đúng luồng đăng nhập sẵn có trong app.
- **Gửi tức thì**: bình luận hiện ngay ở đầu danh sách với trạng thái "Đang gửi…", rồi
  được thay bằng bản của máy chủ khi trả về. Không có màn hình chờ.
- **Gửi lỗi thì không mất chữ**: bình luận được đánh dấu và có nút "Gửi lỗi — thử lại".
- **Trả lời**: hỗ trợ lồng một cấp; trả lời của trả lời được gắn về bình luận gốc nên cây
  không sâu vô hạn. Ô soạn hiện "Đang trả lời …" kèm nút huỷ.
- **Bình luận của người khác** tự xuất hiện nhờ nhịp làm mới mỗi 7 giây trong lúc trang
  còn mở, và làm mới ngay khi app quay lại tiền cảnh.
- **Xoá** chỉ hiện với bình luận của chính mình, có hộp xác nhận, và khôi phục lại nếu
  máy chủ từ chối.

### Tài khoản quản trị

Tên quản trị viên in đậm bằng gradient xanh, kèm huy hiệu **tích xanh động**: vòng tròn
xanh có quầng sáng nhấp nhẹ và dấu tick. Chuyển động chỉ dùng `scaleEffect` và một quầng
sáng nhỏ trên hình 16pt, tự tắt khi bật *Reduce Motion* — bài học từ vòng 24: quầng sáng
lặp vô hạn trên cả danh sách là thứ từng làm app giật.

Huy hiệu hiện khi `userRole` của bình luận chứa `admin`/`quantri`/`moderator`, hoặc khi
email người gửi nằm trong `CommentAuthor.fallbackAdminEmails` (dự phòng cho tới khi
backend trả `role`).

### Khi backend chưa có endpoint

Ba procedure bình luận hiện **chưa tồn tại** trên máy chủ (đã kiểm tra trực tiếp: tRPC
trả 404 cho mọi tên thử). Vì vậy app:

1. Thử gọi máy chủ trước.
2. Gặp 404 → tự chuyển sang lưu bình luận trong Application Support của thiết bị, hiện
   một dòng nhỏ "Máy chủ chưa bật bình luận, nội dung đang được lưu trên thiết bị này".
3. Ngay khi backend bổ sung ba procedure theo `COMMENTS-BACKEND.md`, app tự quay về chế
   độ máy chủ — không cần sửa client.

## 29. Dịch vụ bình luận PHP chạy trên cPanel

Vì backend chính chưa có procedure bình luận, kèm thêm một gói PHP độc lập để chạy
tính năng này trên hosting cPanel mà không cần đụng vào backend hiện tại.

### Nội dung gói `cpanel-comments/`

| Tệp | Vai trò |
| --- | --- |
| `index.php` | Định tuyến `cinema.comments`, `cinema.addComment`, `cinema.deleteComment`, `health` |
| `lib/Auth.php` | Xác thực bằng cách gọi `auth.me` của máy chủ chính với cookie phiên được chuyển tiếp |
| `lib/Store.php` | Lưu trữ SQLite/MySQL, kiểm tra dữ liệu, chống spam, luật xoá |
| `lib/Respond.php` | Trả về đúng envelope tRPC mà app đang đọc |
| `.htaccess` | Đưa `/api/trpc/...` về `index.php`, chặn truy cập `data/`, `lib/`, `config.php` |
| `README.md` | Hướng dẫn upload và xử lý sự cố |

### Phía app

- `COMMENTS_API_BASE_URL` trong `project.yml` / `Info.plist`: để trống thì dùng máy chủ
  chính, điền tên miền phụ thì gọi dịch vụ riêng. Cùng một đường dẫn `/api/trpc/…` nên
  không phải sửa gì khác.
- Khi máy chủ bình luận ở tên miền khác, app gửi kèm cookie phiên của máy chủ chính
  trong header `Cookie`, nhờ đó dịch vụ biết ai đang đọc và ai đang gửi.

### Kiểm thử đã chạy

Dựng máy chủ chính giả để trả `auth.me` theo cookie, rồi chạy 19 bài kiểm thử đầu-cuối
qua chính `.htaccess` mô phỏng: health, danh sách rỗng, slug sai, procedure lạ (404),
gửi khi chưa đăng nhập (401), người dùng thường gửi, admin trả lời, `isMine` nhìn từ
hai tài khoản, chống spam, trả lời vào bình luận không tồn tại, trả lời sai phim, người
dùng thường xoá bình luận của admin (bị từ chối), admin xoá (được, xoá cả trả lời),
email dự phòng trong `admin_emails` thành admin, nội dung quá dài, nội dung rỗng.
Tất cả trả về đúng như mong đợi.

## 30. Ba procedure bình luận thêm thẳng vào backend tRPC sẵn có

Trong zip có cả backend (`server/`, `drizzle/`), nên tính năng bình luận được nối vào
đúng chỗ thay vì bắt bạn dựng thêm dịch vụ. Bốn tệp được sửa, theo đúng quy ước đang
dùng trong dự án:

| Tệp | Thay đổi |
| --- | --- |
| `drizzle/schema.ts` | Bảng `movie_comments` + hai chỉ mục, cùng kiểu khai báo với `movie_favorites` |
| `server/db.ts` | `ensureMovieCommentsCompatibility` (tạo bảng lúc khởi động), `listMovieComments`, `findMovieComment`, `addMovieComment`, `deleteMovieComment` |
| `server/routers.ts` | `cinema.comments` (công khai), `cinema.addComment`, `cinema.deleteComment` (yêu cầu đăng nhập) |
| `server/securityRateLimit.ts` | `commentPerUser`: 20 bình luận mỗi phút cho mỗi tài khoản |

Chi tiết đáng chú ý:

- **Bảng tự tạo khi khởi động** qua `initializeDatabase`, đúng cách các bảng mới khác
  (`qr_login_challenges`, `account_sessions`) đang làm — không cần chạy migration tay.
- **Vai trò quản trị lấy từ chính bảng `users`**: `users.role` đã là enum `user | admin`,
  nên bình luận do tài khoản admin gửi sẽ mang `userRole = "admin"` và app gắn huy hiệu
  tích xanh mà không cần cấu hình thêm.
- **Luật xoá**: chủ bình luận hoặc quản trị viên. Xoá bình luận gốc xoá luôn các trả lời
  trực thuộc nên không còn trả lời mồ côi.
- **Trả lời**: kiểm tra bình luận gốc có thật và thuộc đúng phim trước khi ghi.
- **Định dạng trả về** trùng với bản PHP (`id`, `parentId`, `content`, `createdAt`,
  `userName`, `userRole`, `userId`, `isMine`), nên hai backend thay thế được cho nhau mà
  app không phải sửa gì.

### Kiểm tra đã chạy

- `npx tsc --noEmit` (strict, `include` gồm `server/**`): **0 lỗi**.
- `npx vitest run`: **14/14 test cũ vẫn pass**.
- Gói PHP độc lập: 19 bài kiểm thử đầu-cuối qua chính `.htaccess` mô phỏng (xem mục 29).

## 31. Sửa lỗi build: trình biên dịch không suy luận kịp trong CommentModels.swift

Codemagic báo ba lỗi cùng một dạng:

```
CommentModels.swift:96:9:  the compiler is unable to type-check this expression in reasonable time
CommentModels.swift:239:25: the compiler is unable to type-check this expression in reasonable time
CommentModels.swift:254:9:  the compiler is unable to type-check this expression in reasonable time
```

### Nguyên nhân

Ba chỗ đó là các chuỗi `??` nối tiếp để thử nhiều tên trường, mỗi mắt là một lần
`try container.decodeIfPresent(...)`:

```swift
name = try container.decodeIfPresent(String.self, forKey: .name)
    ?? container.decodeIfPresent(String.self, forKey: .userName)
    ?? container.decodeIfPresent(String.self, forKey: .user_name)
    ?? container.decodeIfPresent(String.self, forKey: .displayName)
    ?? container.decodeIfPresent(String.self, forKey: .display_name)
```

Mỗi `decodeIfPresent` vừa là hàm `throws` vừa trả về optional, nên khi nối 5–8 mắt lại,
bộ suy luận kiểu của Swift phải xét số tổ hợp tăng theo cấp số nhân. Đây là lỗi nổi
tiếng của Swift, không phải lỗi cú pháp — bản thân đoạn code vẫn đúng.

### Cách sửa

Thay mọi chuỗi `??` bằng một hàm vòng lặp nhỏ, dùng chung cho cả tệp:

```swift
private func firstValue<T: Decodable, K: CodingKey>(
    _ type: T.Type,
    in container: KeyedDecodingContainer<K>,
    keys: [K]
) throws -> T? {
    for key in keys {
        if let value = try container.decodeIfPresent(T.self, forKey: key) {
            return value
        }
    }
    return nil
}
```

Nhờ vậy mỗi lần đọc chỉ còn một lời gọi phẳng, ví dụ:

```swift
let rawName = try firstValue(
    String.self,
    in: container,
    keys: [.authorName, .userName, .user_name, .author, .fullName, .full_name, .name]
)
authorName = rawName ?? nested?.name ?? "Người xem"
```

Đã áp dụng cho toàn bộ `CommentModels.swift`: `NestedCommentAuthor`, `MovieComment`
(id, parentId, nội dung, tên, vai trò, id người gửi, email, thời gian, `isMine`) và
`MovieCommentEnvelope`. Hành vi giải mã không đổi — vẫn nhận đủ mọi cách đặt tên trường,
thời gian ISO/epoch, id dạng chuỗi hoặc số.

Thêm một thay đổi nhỏ: phần bỏ dấu để nhận diện tên quản trị được gom vào
`CommentAuthor.normalize(_:)` và dùng chung, thay vì lặp lại chuỗi xử lý ở hai nơi.

### Đã kiểm

- Quét toàn bộ mã nguồn: không còn chỗ nào có từ ba dấu `??` trở lên, không có dòng nào
  dài quá 320 ký tự trong các tệp mới.
- Kiểm tra cú pháp toàn bộ 26 tệp: 0 lỗi.
- Ba tệp còn lại của tính năng bình luận (`CommentsStore.swift`, `CommentsSection.swift`,
  `CinemaAPI.swift`) đã rà lại theo cùng tiêu chí, không có biểu thức nào thuộc dạng này.

## 32. Bình luận real-time, nhãn quyền tuỳ chỉnh, ghim bình luận, ảnh đại diện

Bốn yêu cầu, làm cùng lúc ở cả ba phần: backend, app iOS và website quản trị.

### 1. Real-time thật sự, không còn chờ theo chu kỳ

Trước đây app làm mới danh sách mỗi 7 giây. Nay có thêm procedure `cinema.watchComments`:
máy chủ **giữ kết nối tối đa 25 giây** và trả về ngay khi phim đó có bình luận mới, xoá
hoặc ghim. Nhờ vậy người khác vừa bình luận là mọi người đang xem phim đó thấy ngay,
không phải chờ hết chu kỳ.

Cơ chế nằm ở `server/commentFeed.ts`: mỗi phim giữ một số `revision` tăng dần, ai đang
chờ thì được đánh thức khi số đó đổi. Vẫn là HTTP thường nên chạy được cả trên hosting
cPanel, không cần websocket. Bộ nhớ được giới hạn ở 500 phim gần nhất.

Nếu máy chủ không hỗ trợ long-poll (ví dụ bạn dùng dịch vụ PHP thay thế), app tự lùi về
làm mới mỗi 6 giây — tính năng vẫn chạy, chỉ chậm hơn.

### 2. Cấp quyền xong là bình luận cũ đổi ngay

Trước đây quyền được lưu kèm từng bình luận lúc gửi, nên cấp admin cho một tài khoản
rồi mà bình luận cũ vẫn trắng trơn, phải bình luận mới thấy tích xanh. Nay **quyền, nhãn
và ảnh đại diện được đọc lại từ bảng `users` mỗi lần tải danh sách**
(`loadCommentProfiles` trong `server/db.ts`). Cấp admin, đổi nhãn hay đổi ảnh đại diện
đều hiện lên ngay ở cả bình luận cũ, không cần bình luận lại.

### 3. Nhãn quyền tuỳ chỉnh, ví dụ "VIP"

- Thêm cột `users.badge` (tối đa 40 ký tự) và procedure `adminAccounts.setBadge`.
- Trên website, trang Quản lý tài khoản có ô "Nhãn hiển thị (badge)" riêng, gợi ý
  `VIP`, `MOD`, `Thành viên vàng`… Bấm lưu là hiện ngay.
- Trên app, tên hiển thị thành `Test v1 (VIP)`. Nhãn và tích xanh độc lập nhau: một tài
  khoản vừa là admin vừa có nhãn sẽ hiện cả hai.

### 4. Ghim bình luận

- Thêm cột `movie_comments.pinnedAt` và procedure `cinema.pinComment` (chỉ admin).
- Bình luận đã ghim luôn nằm đầu danh sách, ghim mới nhất trước; trên app có chip
  "ĐÃ GHIM", trên website có nút Ghim/Bỏ ghim và dấu ghim rõ ràng.
- Sắp xếp ba mức ở app: đang gửi hoặc gửi lỗi → đã ghim → còn lại theo thời gian.

### 5. Ảnh đại diện

- Thêm cột `users.avatar` và hai procedure `account.setAvatar`, `account.clearAvatar`.
- Trong app, vào **Tài khoản & thiết bị**, chạm vào ảnh đại diện để chọn ảnh mới từ thư
  viện, có nút "Xoá ảnh". Ảnh được thu nhỏ về tối đa 256 điểm ảnh và hạ chất lượng dần
  cho tới khi dưới 220 KB (`AvatarUploader`) trước khi gửi.
- Ảnh được nhớ lại trong `AvatarImageCache` nên danh sách bình luận dựng lại liên tục
  cũng không giải mã lại ảnh.
- Đổi ảnh xong, hồ sơ được làm mới ngay nên ảnh mới hiện ở mọi nơi trong app và ở tất cả
  bình luận người đó đã viết — kể cả trên thiết bị khác.

### 6. Trang quản trị phim trên website

Thêm `/admin/movies` (`client/src/pages/AdminMovies.tsx`):

- Cột trái: tìm phim (debounce 350ms, từ 2 ký tự) hoặc duyệt danh sách mới cập nhật;
  bấm để chọn phim, có nút mở phim trên web.
- Cột phải: bình luận của phim đang chọn, **cập nhật trực tiếp** bằng chính
  `watchComments`, kèm nút làm mới tay, nút **Ghim lên đầu / Bỏ ghim** và nút **Xoá**
  (có xác nhận). Có nhãn "Đang cập nhật trực tiếp" và trạng thái rỗng rõ ràng.
- Trang Quản lý tài khoản nay hiện avatar và nhãn của từng tài khoản.

### Kiểm tra đã chạy

- Backend: `npx tsc --noEmit` (strict) **0 lỗi**, `npx vitest run` **14/14 pass**.
- Website: `npx tsc --noEmit` **0 lỗi**, `npx vite build` **thành công**.
- App: kiểm cú pháp toàn bộ 27 tệp **0 lỗi**, mọi ký hiệu mới đều có định nghĩa.

### Điều cần biết

Long-poll, nhãn quyền, ghim và ảnh đại diện đều cần backend Node trong zip này. Dịch vụ
PHP độc lập (`cpanel-comments/`) vẫn chỉ có bình luận cơ bản: app sẽ tự chuyển sang làm
mới mỗi 6 giây, không có ghim và không có nhãn quyền. Website luôn dùng backend Node nên
phần quản trị chạy đủ tính năng trong cả hai trường hợp.

## 32. Tải phim offline, poster và bộ lọc nhiều lựa chọn

### Poster trắng ở một số phim
- **Nguyên nhân**: token ảnh `/api/cinema/image/<token>` chỉ sống **2 giờ**, trong khi
  `Cache-Control` lại khai 2 giờ. Danh sách phim tải về lúc sáng tới chiều là hàng loạt
  poster 404 dù API vẫn trả đúng đường dẫn.
- **Sửa**: token ảnh nay là **URL nguồn mã hoá base64url**, không còn hạn và không cần
  bảng tra trong bộ nhớ. Máy chủ giải mã rồi kiểm tra lại host nằm trong danh sách cho phép.
  Ảnh `http://` cũng được nâng thành `https://` thay vì bị loại (iOS chặn http).

### Tải phim về xem khi không có wifi
- `State/DownloadManager.swift`: nguồn là HLS nên tải bằng playlist — chọn biến thể băng
  thông cao nhất, tải từng phân đoạn theo lô 3 và **ghi theo đúng thứ tự**, nối thành tệp
  `.ts` mà `AVPlayer` phát trực tiếp được.
- Tải tiếp được sau khi tạm dừng: tệp tạm luôn chứa đúng các phân đoạn đầu, nên lần sau
  ghi tiếp từ phân đoạn dang dở.
- Giới hạn **2 tập tải song song**, phần còn lại xếp hàng — tránh nghẽn mạng và hao pin
  khi bấm "Tải tất cả" cho bộ phim dài.
- Nguồn có `#EXT-X-KEY` (AES-128) được đánh dấu **không hỗ trợ** kèm lời giải thích, thay
  vì tải về một tệp hỏng.
- `Views/DownloadsScreen.swift`: màn "Đã tải xuống" hiện tiến trình theo thời gian thực,
  dung lượng đã tải, trạng thái từng tập, tạm dừng/tiếp tục/xoá; bảng `DownloadSheet` cho
  phép chọn nguồn (vietsub, lồng tiếng, thuyết minh…) rồi tải từng tập hoặc tải cả nguồn.
- Trình phát ưu tiên tệp đã tải trong máy, nên phim đã tải phát được khi mất mạng.

### Bộ lọc nhiều lựa chọn
- Thư viện: các nhóm **nguồn phim, thể loại, quốc gia, năm** nay chọn được nhiều giá trị
  cùng lúc (ví dụ Phim Bộ + Phim Lẻ).
- API `cinema.list` nhận mảng `kinds/categories/countries/years`, gộp kết quả của từng tổ
  hợp (tối đa 6 lượt gọi nguồn) rồi khử trùng theo slug.

## 33. Thư mục tải xuống trong cài đặt

- Màn mới `Views/DownloadFolderScreen.swift`, vào từ tab **Lưu → Thư mục tải xuống** hoặc
  nút **Thư mục** ở màn Đã tải xuống.
- **Thư mục mặc định** chuyển từ `Application Support/Cinemora/Downloads` sang
  `Documents/Downloads`, kèm `UIFileSharingEnabled` và `LSSupportsOpeningDocumentsInPlace`
  trong `Info.plist` — nhờ vậy thư mục hiện được trong app Tệp và nút **Mở thư mục** hoạt động.
- **Chọn thư mục khác**: `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`,
  lưu quyền truy cập bằng security-scoped bookmark trong `UserDefaults`. Bookmark được làm mới
  khi cũ (stale) và **tự quay về thư mục mặc định kèm thông báo** nếu quyền bị thu hồi, thay vì
  để mọi bản tải xuống thất bại trong im lặng.
- **Dùng thư mục mặc định**: trả bookmark, chuyển các tệp `.ts` đã tải về lại.
- Đổi thư mục thì **di chuyển tệp đã tải** sang thư mục mới (bỏ qua tệp đã có ở đích).
- Màn cài đặt hiển thị đường dẫn đầy đủ, dung lượng đã tải và dung lượng còn trống của thiết bị.
- Sửa lỗi phát hiện khi rà lại: thuộc tính `maxConcurrent` của hàng đợi tải chưa được chèn ở
  lần vá trước (bản build sẽ không biên dịch được), nay đã bổ sung cùng hàng đợi 2 tập song song.

## 34. Sửa lỗi build IPA

Ba lỗi biên dịch và cách xử lý:
- `CinemoraApp.swift:338 cannot find 'downloads' in scope`: dòng inject trùng được thêm vào
  `TabShell` (view không có `downloads` trong phạm vi). Gốc app đã inject sẵn cho cả cây view
  nên dòng trùng được bỏ.
- `DownloadManager.swift:70 use [:] to get an empty dictionary literal`: `tasks` là từ điển nên
  khởi tạo phải là `[:]`, không phải `[]`.
- `LibraryScreen.swift:214 argument 'reset' must precede argument 'kinds'`: Swift yêu cầu tham
  số theo đúng thứ tự khai báo, nên lời gọi phân trang đổi thành
  `loadCatalog(kind:reset:kinds:categories:countries:years:)`.

## 35. Tiến trình theo dung lượng, mở thư mục, dừng/xoá tải

### Vì sao "Mở thư mục" báo không mở được
`UIApplication.open` chỉ mở **tệp** hoặc **app**, không mở được URL trỏ tới một thư mục — nên
lệnh cũ luôn thất bại. Nay dùng scheme riêng của app Tệp: `shareddocuments://<đường dẫn>`.
Kèm hai lớp dự phòng: nút **Sao chép đường dẫn** (chắc chắn dùng được) và thông báo hướng dẫn
cụ thể `Tệp → Trên iPhone của tôi → Cinemora → Downloads`.

### Màn Đã tải xuống
- Hai nhóm tách bạch: **Đang tải (n)** và **Đã tải (n)**, kèm hành động gộp
  **Dừng tất cả** / **Xoá tất cả** (xoá tất cả chỉ tác động bản đã tải xong).
- Mỗi dòng: thanh tiến trình, **dung lượng đã tải trên tổng dung lượng ước tính**
  (`1,2 GB / 50 GB`), phần trăm, tốc độ (`MB/s`), thời gian còn lại và số phân đoạn.
- Nút **Dừng tải** / **Tiếp tục** / **Xoá tải** cho từng tập.

### Ước tính tổng dung lượng
Playlist HLS không khai dung lượng tệp, nên tổng dung lượng được suy ra hai cách: băng thông
`#EXT-X-STREAM-INF` nhân tổng thời lượng `#EXTINF` (trước khi tải), và số đo thực tế
(trung bình phân đoạn × số phân đoạn) khi đã xong từ 3 phân đoạn. Nếu hai con số lệch nhau
hơn 3 lần (playlist tổng khai băng thông cao hơn thực tế) thì tin vào số đo.

## 36. Xem tệp trong app, gộp mục tải xuống, sửa lỗi khi bấm Dừng

### "Mở thư mục" thay bằng trình duyệt tệp trong app
Mở thư mục bằng app Tệp không đáng tin trên iOS (và bất khả thi với thư mục nằm ngoài vùng
lưu của app). Nay nút **Xem tệp đã tải** mở `DownloadedFilesBrowser` — danh sách tệp ngay
trong app: tên tệp, dung lượng, ngày tải, nút **Chia sẻ** cho từng tệp và nút **Xoá tệp**.
Xoá tệp thì mục tương ứng trong danh sách tải xuống cũng được gỡ (tra theo `fileName`).

### Gộp hai mục trong tab Lưu
Bỏ mục riêng "Thư mục tải xuống"; tab Lưu chỉ còn **Đã tải xuống**. Toàn bộ cài đặt thư mục
(đường dẫn hiện tại, dung lượng, chọn thư mục khác, sao chép đường dẫn, dùng mặc định) nằm
cuối màn này trong khối `DownloadFolderSection`. Đã bỏ dòng ghi chú về quyền truy cập iOS.

### Nút trở ra
Màn Đã tải xuống có nút **Trở lại** ở đầu và vuốt từ mép trái sang phải để trở ra (dải nhận
vuốt 16pt, không cản việc cuộn danh sách).

### Sửa lỗi báo lỗi khi bấm Dừng
Khi tác vụ tải bị huỷ, `URLSession` ném `URLError(.cancelled)` — **không phải**
`CancellationError` như mã cũ chỉ bắt. Vì vậy lỗi rơi vào nhánh xử lý chung và hiện
"Tải thất bại…" dù không có lỗi gì. Nay: trạng thái được đánh dấu tạm dừng **trước** khi huỷ,
cả hai loại lỗi huỷ đều xử lý như tạm dừng, và nhánh lỗi chung từ chối ghi đè trạng thái đã
tạm dừng. Bấm Dừng chỉ hiện "Tạm dừng", giữ nguyên tiến trình; bấm **Tiếp tục** thì ghi tiếp
từ phân đoạn dang dở chứ không tải lại từ đầu.

## 37. Xoá trong app là xoá luôn tệp trong thư mục

- `DownloadManager.remove(_:)` xoá **tệp phim thật** trong thư mục tải xuống rồi mới bỏ mục
  khỏi danh sách — người dùng không phải xoá thủ công lần nữa. "Xoá tất cả" cũng vậy.
- Nếu tệp không xoá được (mất quyền truy cập thư mục đã chọn), mục được **giữ lại kèm lời
  báo** thay vì biến mất trong khi tệp vẫn chiếm dung lượng máy.
- Thêm `deleteFile(at:)` cho trình duyệt tệp: xoá tệp trước, chỉ gỡ mục khi tệp đã xoá xong,
  báo lỗi ngay trong màn duyệt nếu thất bại.
- Màn Đã tải xuống ghi rõ: "Xoá ở đây là xoá luôn tệp trong thư mục".

## 38. Sửa lỗi build: invalid redeclaration of 'FolderPicker'

Nguyên nhân: lần trước tôi **đổi tên** `Views/DownloadFolderScreen.swift` thành
`DownloadFolderSection.swift`. Khi cập nhật vào repo, tệp cũ vẫn còn nên tồn tại hai tệp cùng
khai báo `FolderPicker` (và `DownloadFolderSection`, `DownloadedFilesBrowser`) → trùng khai báo.

Cách xử lý: **trả lại tên tệp gốc** `Views/DownloadFolderScreen.swift` để bản mới ghi đè bản cũ
khi cập nhật, và xoá tệp `Views/DownloadFolderSection.swift` còn sót trong repo. Trong gói phát
hành chỉ còn đúng một tệp, không còn tên nào trùng.

## 39. Dọn màn tải xuống, định dạng dung lượng, chặn tải khi thiếu chỗ

- Bỏ nút **Sao chép đường dẫn** và hai dòng ghi chú dài trong màn Đã tải xuống / bảng tải
  xuống (phần nói về AES-128 và cách chọn nguồn).
- Lỗi hiển thị **"Zero KB"**: `ByteCountFormatter` trả về đúng chuỗi đó cho giá trị 0. Toàn app
  nay dùng hàm chung `auroraByteText()` trả về **"0 KB"**.
- **Chặn tải khi thiếu dung lượng** (ba lớp):
  1. Khi bấm "Tải tất cả N tập", hệ thống ước tính dung lượng một tập từ playlist rồi nhân cho
     số tập, cộng phần đang chờ tải; vượt dung lượng trống thì **không xếp hàng** và báo rõ
     "cần khoảng X, máy còn Y — hãy chọn bớt tập hoặc tải lượng phim thấp hơn dung lượng còn trống".
  2. Mỗi tập khi bắt đầu tải đều được kiểm tra lại theo số đo thật của playlist; thiếu chỗ thì
     dừng ngay kèm lời báo, không tải dở rồi mới lỗi.
  3. Trong lúc tải, nếu dung lượng trống xuống dưới 300 MB thì tạm dừng và báo để người dùng
     xoá bớt phim rồi bấm Tiếp tục.

## 40. Nguồn và tập phim thêm thủ công (website admin + app)

Phim lấy từ API giờ có thể được admin bổ sung nguồn và tập riêng ngay trên website.

- **Bảng dữ liệu mới**: `movie_sources` (nguồn theo slug phim) và `movie_source_episodes`
  (tập: tên, link M3U8, link phụ đề, nội dung VTT tải lên). Có hàm
  `ensureMovieSourcesCompatibility` tự tạo bảng khi khởi động trên hosting.
- **Lớp nghiệp vụ** `server/movieSources.ts`: thêm/xoá/đổi tên nguồn, thêm/sửa/xoá/sắp xếp tập,
  lưu phụ đề tải lên và tự **chuyển SRT sang WebVTT** (AVPlayer chỉ đọc được VTT).
- **Ghép vào API chi tiết phim**: `cinema.detail` trả thêm nguồn thủ công vào `servers`, mỗi tập
  có cả link M3U8 gốc (`directStreamUrl`) và link qua proxy (`streamUrl`), kèm `subtitle_url`.
- **Route công khai** `GET /api/movies/subtitle/:id.vtt` trả file phụ đề đúng chuẩn `text/vtt`.
- **App**: không cần thêm mã — nguồn thủ công hiện như nguồn bình thường, phụ đề do
  `episode.subtitleURL` nạp vào `AVPlayerItem` nên hiển thị đúng tiến trình phim và khi tua.
- **Website admin**: trang `/admin/movies/sources?slug=...` xem nguồn/tập gốc từ API (chỉ đọc)
  và quản lý nguồn thêm thủ công, kèm nút "Nguồn & tập" ở danh sách phim.

## 41. Sửa bộ lọc cho chuẩn và hiển thị số phim chính xác

Bộ lọc nhiều lựa chọn trước đây gộp kết quả theo từng tổ hợp nhưng **chỉ lấy 6 tổ hợp
đầu**, trả về `pagination` của tổ hợp đầu tiên (nên "tổng số phim" và số trang sai) và
không kiểm tra lại phim có đúng lọc hay không — đó là lý do lọc ra phim không đúng.

- **Máy chủ**: `getMovies` viết lại — dựng đủ tổ hợp lọc (OR trong cùng nhóm, AND giữa các
  nhóm), gọi song song, gộp và khử trùng theo slug, sắp xếp theo thời gian cập nhật, và
  **kiểm tra lại từng phim** bằng `matchesCombo` (đúng thể loại, quốc gia, năm) nên không
  thể lọt phim sai. Quá 12 tổ hợp thì báo lỗi rõ ràng thay vì âm thầm bỏ bớt lọc.
- **Số liệu**: một tổ hợp lọc → dùng đúng tổng số phim của nguồn; nhiều tổ hợp → trả `null`
  thay vì một con số sai (vẫn còn `hasNextPage` để cuộn tiếp).
- **Đếm số phim theo từng lựa chọn** (`cinema.filterCounts`): mỗi lựa chọn được đếm bằng một
  truy vấn chỉ có một giá trị mỗi nhóm nên con số chính xác theo các lọc khác đang bật
  (đã đối chiếu: Hành động + Phim Bộ = 1.188 khớp truy vấn trực tiếp).
- **App**: chip lọc hiện thêm số phim ("Hành động · 7.711"), tiêu đề hiện tổng số phim chính
  xác khi có, và ghi rõ "N phim đã tải" khi bộ lọc nhiều tổ hợp không có tổng.
- **Website**: nút "Trang sau" hoạt động cả khi không có tổng số trang (dựa vào `hasNextPage`).

## 42. Sửa phụ đề của nguồn thêm thủ công không hiện trong app

Hai lỗi cộng lại làm phụ đề thêm tay không bao giờ hiện:

- **Trình phát**: điều kiện hiện phụ đề là `hasCurrentSubtitle` nhưng hàm này còn đòi cờ
  `subtitleCustomizationEnabled` — cờ chỉ được bật ở màn Truyền Hình. Phim lẻ/phim bộ vì
  thế vẫn **nạp** phụ đề rời nhưng **không vẽ** ra. Giờ tách thành `subtitleAvailable`
  (chỉ cần tập có phụ đề), và phụ đề song ngữ cũng được nạp cùng.
- **Máy chủ**: `toEpisode` trả thẳng link ngoài admin dán vào; nếu link là SRT hoặc máy chủ
  nguồn chặn tải thì app không đọc được gì. Giờ mọi tập có phụ đề đều trỏ về
  `/api/movies/subtitle/<id>.vtt`: máy chủ trả VTT đã lưu, hoặc tự tải link ngoài và
  **đổi SRT → WebVTT** rồi trả về; nếu vẫn không tải được thì `302` sang link gốc để trình
  phát tự thử.
- **Lúc lưu**: `addMovieEpisode` / `updateMovieEpisode` đổi link phụ đề sang WebVTT ngay khi
  admin bấm Thêm tập, nên lúc xem không phải chờ và không phụ thuộc nguồn cho tải lại.
  Link sai thì vẫn lưu nhưng phần phụ đề để trống.
- Phim lẻ/phim bộ được bật luôn tuỳ chỉnh phụ đề (cỡ chữ, vị trí) như Truyền Hình.

## 43. Sửa gốc: phụ đề dạng `MM:SS.mmm` bị bỏ + báo trạng thái nạp phụ đề

- **Bộ đọc phụ đề**: hàm `parseTime` cũ đòi mốc thời gian phải **đủ 3 phần**
  `HH:MM:SS.mmm`. WebVTT cho phép `MM:SS.mmm` và nguồn phim phát đúng dạng đó, nên phần
  lớn câu phụ đề bị bỏ lặng lẽ. Đo trên file thật của người dùng: thuật toán cũ đọc được
  **1376/2344 câu**, thuật toán mới đọc đủ **2344 câu**. Bộ đọc mới nhận cả
  `HH:MM:SS.mmm`, `MM:SS.mmm`, `SS.mmm`, dấu `,` của SRT, file không có dòng trống giữa
  các câu, có BOM, và tự bỏ thẻ định dạng (`<i>`, `{\an8}`).
- **Tải phụ đề**: gửi header giống trình duyệt (UA + Accept) và thử thêm bảng mã
  Latin-1 nếu file không phải UTF-8 — vài CDN phim chặn client lạ.
- **Thấy được tình trạng**: tab Phụ đề hiện “Đã nạp N câu phụ đề” hoặc “Không tải được
  phụ đề — kiểm tra lại link phụ đề”, thay vì im lặng như trước.

## 44. Bốn sửa đổi trải nghiệm

- **Danh sách tập khi tải (phim 1000+ tập) hết khựng**: danh sách tập trong sheet Tải
  xuống dùng `LazyVStack` thay `VStack`, chỉ dựng những hàng đang nhìn thấy. Trước đây mở
  sheet là tạo hết mọi hàng cùng lúc, nên phim nhiều tập bị lag, phim ít thì không.
- **Bộ lọc bỏ số phim**: chip lọc chỉ còn tên (“Bí Ẩn” thay vì “Bí Ẩn · 3.446”), bỏ luôn
  vòng xoay chờ đếm và **ngừng gọi máy chủ đếm số** — nhanh hơn và gọn hơn.
- **Nút trở lại mượt hơn + vuốt cạnh**: nhịp bấm đổi sang spring `0.18` (nhanh, dứt khoát),
  vùng bấm phủ cả viên thuốc (`contentShape`), và mọi màn chỉ có nút trở lại đều được thêm
  **kéo từ mép trái sang phải để trở ra** (Lịch sử, Yêu thích, Cài đặt phát, Tài khoản &
  thiết bị, Tải xuống, sheet tải tập, màn xem thêm ở Trang Chủ). Vuốt cạnh giờ nhận cả cú
  hất nhẹ nhờ `predictedEndTranslation`.
- **Trình phát không ẩn công cụ khi còn đang tải**: trước đây `isPlaying` bật ngay khi gọi
  `play()` nên sau 4 giây công cụ bị ẩn dù nguồn chưa phát được. Giờ chỉ ẩn khi phim đã
  chạy thật (`!isLoading` và không có lỗi); đang tải thì giữ nguyên công cụ, tải xong mới
  đếm giờ ẩn, còn lỗi thì hiện thông báo lỗi kèm nút **Trở lại**.

## 45. Sửa lỗi build: bộ kiểm tra kiểu quá tải ở trình phát

Codemagic báo `CinemaPlayerScreen.swift:860: the compiler is unable to type-check this
expression in reasonable time`. Đây không phải lỗi cú pháp mà là **bộ kiểm tra kiểu của
Swift bỏ cuộc** trước thân `body` quá lớn của trình phát: hàng chục modifier, mỗi cái một
closure, cộng thêm vài closure dài và biểu thức optional lồng nhau.

Cách sửa: tách các closure nặng ra hàm riêng, thân `body` chỉ còn lời gọi một dòng —
`handlePlayerDisappear()`, `handleSubtitlePreferencesChange(_:)`, `handleStopAtEpisodeToggle(_:)`,
`handleLoadingChange(_:)`, `handlePlaybackErrorChange()`. Giữ nguyên 100% hành vi, chỉ đổi
chỗ đặt mã, và tránh lặp lại lỗi này khi thêm hiệu ứng về sau.

## 46. Truyền hình: vào ngang ngay, live chạy luôn

- **Video đã đăng mở thẳng ở tư thế ngang**: trước đây `fullScreenCover` hiện ra ở tư
  thế dọc rồi mới tự xoay ngang. Giờ cả kênh live lẫn video đã đăng đều đi qua
  `presentPlayer()` → `OrientationSupport.rotateThenPresent`, tức xoay trước rồi mới mở,
  giống màn chi tiết phim. Khi thoát, `TVVideoFullscreenPlayer` trả màn hình về dọc
  (trước đây thiếu bước này nên app dễ kẹt ở tư thế ngang).
- **Live chạy ngay, không phải bấm “Đồng bộ”**: `load()` trước đây gọi
  `playImmediately` ngay sau khi gắn item, nên AVPlayer đứng ở đầu cửa sổ DVR và phải bấm
  Đồng bộ mới xem được. Giờ `load()` và `syncToLiveEdge()` dùng chung `startLiveItems()`:
  gắn item → đợi `readyToPlay` → chờ thêm nếu chưa có `seekableTimeRanges` → seek về mép
  phát trực tiếp → chạy. Bấm Đồng bộ vẫn dùng đúng luồng đó.

## 47. Thêm phim thủ công bằng link (web admin + app)

**Backend**
- Bảng mới `custom_movies` (tên, tên tiếng Anh, tên khác, tập hiện tại, ngày tạo, TMDB, IMDB,
  thể loại, quốc gia, đánh giá, lượt xem thật/ảo, poster, thumbnail, nội dung, diễn viên có ảnh,
  đạo diễn, loại phim, trạng thái) + cột `qualities` cho `movie_source_episodes`.
- `ensureCustomMoviesCompatibility` tự tạo bảng/cột khi máy chủ khởi động — không cần SQL tay.
- `server/customMovies.ts`: CRUD, lưu ảnh (kiểm tra magic bytes, ≤ 8MB), sinh slug không dấu,
  trộn vào danh sách/tìm kiếm/trang chủ, trang chi tiết riêng, đếm lượt xem thật.
- Phim thủ công trả về **cùng hình dạng `Movie`/`MovieDetail`** với phim API nên app không phải
  xử lý riêng: hiện đủ tên tiếng Anh, tên khác, thể loại, quốc gia, đánh giá, lượt xem, diễn viên
  kèm ảnh, ngày tạo/cập nhật, TMDB/IMDB.
- Mỗi tập có **nhiều chất lượng**, mỗi chất lượng có link M3U8 và phụ đề riêng; link phụ đề ngoài
  được đổi sang WebVTT và lưu thành tệp để phát đúng tiến trình khi tua.

**Web admin**
- Trang `/admin/movies/custom/new` và `/admin/movies/custom/:id` (nút “+ Thêm phim thủ công”
  trong Quản lý phim): biểu mẫu đầy đủ, chọn nhiều thể loại/quốc gia, chip tên khác/đạo diễn bằng
  Enter, lượt xem thật/ảo, diễn viên có ảnh, quản lý nguồn – tập – chất lượng.
- `ImagePicker`: tải ảnh hoặc dán link, có trình cắt ảnh (Poster 2:3, Thumbnail 16:9, Diễn viên 1:1,
  tự do) rồi tải lên máy chủ.

**App**
- `MovieEpisode.qualities` + `withQuality(_:)`: trình phát có mục **Chất lượng** (tab Hiển thị),
  đổi chất lượng nạp lại đúng vị trí đang xem kèm phụ đề của chất lượng đó.


## 48. Tinh chỉnh giao diện trang "Thêm phim thủ công"

- **Loại phim**: thay `<select>` mặc định của trình duyệt bằng ô chọn tuỳ biến (nút mở, mũi tên xoay,
  danh sách nổi có dấu tích, đóng khi bấm ra ngoài hoặc nhấn Esc).
- **Thể loại / Quốc gia**: mỗi bộ chọn thành một thẻ riêng có: hàng chip "đã chọn" bấm để bỏ nhanh,
  ô tìm kiếm có nút xoá, hai lệnh nhanh "Chọn tất cả" / "Bỏ chọn hết", lưới chip cao hơn với thanh
  cuộn mảnh màu accent thay cho thanh cuộn mặc định thô.
- **Đạo diễn**: dùng chung ô nhập chip như "Tên khác", có tiêu đề và gợi ý rõ ràng, đặt ngay trên
  danh sách diễn viên.
- **Diễn viên**: bỏ mục "Vai diễn"; mỗi thẻ chỉ còn tên và ảnh (không bắt buộc) kèm ảnh tròn xem trước,
  ảnh diễn viên dùng khung phẳng gọn bên trong thẻ.
- **Lượt xem**: đổi hai nút radio thành thanh chọn phân đoạn; phần "Số ảo cộng thêm" chỉ hiện khi chọn
  "Thật + ảo".
- **Thanh lưu**: bám đáy khung (sticky) để luôn bấm được khi cuộn dài; khi tạo phim mới hiện gợi ý
  "Lưu phim trước, sau đó thêm nguồn và tập ở khung bên phải".
- Khung bên phải khi chưa lưu phim hiện thẻ "Nguồn & tập — Lưu phim trước" thay vì để trống.


## 49. Dán link ảnh: tự tải về và hiện xem trước

- Ô dán link ảnh (Poster, Thumbnail, ảnh diễn viên) giờ **tự động tải ảnh** sau khi bạn dán/gõ
  link (chờ 0,7 giây, hoặc tải ngay khi rời ô nhập), hiện ảnh xem trước kèm vòng xoay "Đang tải
  ảnh từ link…", rồi báo "Sẵn sàng" cùng ghi chú *Đã tải ảnh về máy chủ — bấm "Chỉnh sửa" nếu
  cần cắt lại*.
- Máy chủ có thêm `customMovies.importImage`: tải ảnh từ link, kiểm tra bằng magic bytes
  (JPEG/PNG/WebP, tối đa 8MB, hết thời gian 20 giây) rồi lưu vào `uploads/movie-images`.
  Nhờ vậy **cắt ảnh luôn hoạt động** (không phụ thuộc CORS của nơi lưu ảnh) và ảnh vẫn còn khi
  link gốc hỏng.
- Chặn địa chỉ nội bộ (localhost, 10.x, 127.x, 172.16–31.x, 192.168.x, 169.254.x, IPv6 nội bộ)
  để link do admin nhập không dùng được để quét mạng nội bộ của máy chủ.
- Nếu không tải được về máy chủ, ảnh vẫn dùng link gốc và có ghi chú cảnh báo có thể không cắt được.


## 50. Sửa lỗi poster sau khi dán link + tìm diễn viên tự động

**Sửa lỗi "Poster phải là URL hợp lệ"** khi tạo phim sau khi dán link ảnh: ảnh đã được tải về
máy chủ nên ô nhập giữ đường dẫn `/uploads/movie-images/…`, nhưng hàm kiểm tra cũ chỉ chấp nhận
URL đầy đủ. Nay đường dẫn nội bộ (`/uploads/…`, `/api/…`) được coi là hợp lệ.

**Tìm diễn viên tự động (mục 04 — Diễn viên & đạo diễn):** gõ tên diễn viên, hệ thống tự tìm
sau 0,45 giây và hiện danh sách gợi ý kèm ảnh, mô tả và mã IMDb; bấm một gợi ý là thêm ngay
diễn viên (kèm ảnh) vào phim, trùng tên thì bỏ qua.

- Nguồn: **TMDB** nếu có biến môi trường `TMDB_API_KEY` (hoặc `TMDB_ACCESS_TOKEN`); nếu chưa có
  thì dùng **Wikidata** miễn phí (tên, mô tả, ảnh Wikimedia Commons, mã IMDb P345) — không cần
  khoá vẫn chạy được.
- Kết quả nhớ tạm 10 phút; loại bỏ gợi ý không phù hợp; TMDB lỗi thì tự chuyển sang Wikidata.
- Thêm `TMDB_API_KEY=…` vào môi trường trên hosting là có ngay kết quả TMDB đầy đủ hơn.


## 51. Tinh chỉnh tìm diễn viên

- Danh sách gợi ý chỉ hiện **ảnh + tên diễn viên**; bấm là thêm ngay.
- Khi dùng TMDB: chỉ lấy người thuộc nhóm **Acting**, ưu tiên bí danh Latinh khớp từ khoá
  (송혜교 → *Song Hye-kyo*), lấy thêm mã IMDb, ảnh lấy từ hồ sơ chi tiết nếu kết quả tìm kiếm thiếu.
- Thêm `TMDB_API_KEY` (v3) hoặc `TMDB_ACCESS_TOKEN` (v4) vào môi trường hosting để dùng TMDB;
  đã ghi hướng dẫn trong `DEPLOY-CPANEL-VI.md` và `.env.example`.


## 52. Tìm diễn viên trên hosting, ô nhập và bộ chọn thể loại/quốc gia

**Tìm diễn viên không ra kết quả:** nguyên nhân thường gặp là hosting chưa nạp biến môi trường
(chưa Restart), chặn kết nối ra ngoài, hoặc Node cũ. Nay:

- Lớp gọi mạng dùng `node:https` thay cho `fetch` toàn cục → chạy được cả trên Node 16/17 của cPanel.
- Thông báo lỗi nêu rõ nguyên nhân thật (mã 401 khi khoá sai, mã khác, hết thời gian, không kết nối được…).
- Thêm nút **Kiểm tra kết nối** cạnh ô tìm diễn viên: hiện phiên bản Node, khoá TMDB đã nạp hay chưa
  (che bớt ký tự), trạng thái TMDB và Wikidata.

**Ô nhập không còn khung vuông lồng:** quy tắc focus của form (`.custom-form-section input:focus`)
áp cả vào ô nhập bên trong khung tìm kiếm. Nay ô nhập trong `.actor-search-input` và `.custom-search`
được bỏ viền/đổ bóng khi focus.

**Thể loại & Quốc gia:** bỏ thanh cuộn lồng, chip dạng viên thuốc, chip đã chọn nền xanh nổi bật,
hiện 16 mục kèm nút **Xem thêm N mục / Thu gọn**, tiêu đề hiện số lượng đã chọn.


## 53. Sửa "Không kết nối được nguồn" trên hosting

Hosting báo Node v22 nhưng cả TMDB lẫn Wikidata đều không kết nối được, thông báo trống tên lỗi.
Nguyên nhân thường gặp: máy chủ có bản ghi IPv6 nhưng không đi ra ngoài được, hoặc tường lửa chặn.

- Lớp gọi mạng nay **tự thử lại một lần chỉ dùng IPv4** khi lần đầu thất bại.
- Thông báo lỗi kèm **mã lỗi thật** (`ENETUNREACH`, `EAI_AGAIN`, `ECONNREFUSED`, `ETIMEDOUT`…),
  kèm địa chỉ và lỗi gốc để biết chính xác vì sao.
- Nút **Kiểm tra kết nối** thêm dòng *Kết nối ra ngoài* (thử `https://example.com`) để phân biệt
  “máy chủ không ra được Internet” với “chỉ nguồn này bị chặn”.


## 54. Tìm diễn viên trực tiếp từ trình duyệt

Hosting cho thấy *Kết nối ra ngoài: hoạt động* nhưng TMDB và Wikidata đều `ETIMEDOUT` — tức máy chủ
bị chặn riêng hai tên miền nước ngoài này (thường gặp ở hosting Việt chỉ mở outbound cho một số đích).

- Trang quản trị nay **tự tìm diễn viên từ trình duyệt của admin** khi máy chủ thất bại:
  gọi TMDB (TMDB mở CORS), không có kết quả thì sang Wikidata (`origin=*`).
- Có ghi chú cho biết kết quả lấy từ trình duyệt; nút *Kiểm tra kết nối* thêm dòng **Từ trình duyệt**.
- Khoá TMDB cấp cho trang quản trị qua procedure chỉ dành cho admin (`actorSearchCredentials`).


## 55. Tìm diễn viên nhanh hơn

- Máy chủ hosting bị chặn nguồn: sau lần thất bại đầu tiên, hệ thống **ghi nhớ** (localStorage, hết hạn 24 giờ)
  và các lần tìm sau **đi thẳng từ trình duyệt**, không chờ máy chủ nữa.
- Kết quả theo từng từ khoá được **nhớ tạm** trong phiên nên gõ lại là hiện ngay.
- Nút *Kiểm tra kết nối* tự đặt/xoá cờ này theo kết quả, và bỏ thử lại IPv4 khi lỗi là hết thời gian
  (timeout mặc định của lớp gọi mạng giảm từ 12s xuống 6s) để phản hồi nhanh.


## 56. Dọn giao diện Thêm phim thủ công

- Bỏ nút **Kiểm tra kết nối** và bảng trạng thái (không còn cần thiết vì điền tên diễn viên là ra kết quả).
- Bộ chọn **Thể loại / Quốc gia** hiện **đầy đủ danh sách từ API**, bỏ nút *Xem thêm*.
- Hai khung được cân lại: cột chia đều, ô tìm kiếm cao bằng nhau, biểu tượng canh giữa,
  hàng *Chọn tất cả / Bỏ chọn hết* thẳng hàng, hai khung cao bằng nhau.

## 57. Nháp khi tạo phim, khung Nguồn & tập, icon tìm kiếm và phim thủ công trên app

- **Nháp tự động**: sau khi tạo phim thành công, 4 phần (Thông tin phim, Hình ảnh, Nội dung,
  Diễn viên & đạo diễn) được lưu lại; mở *Phim mới* lần sau sẽ tự điền sẵn, kèm dòng nhắc và nút
  **bắt đầu mới** để xoá nháp.
- **Khung Nguồn & tập** to hơn: cột phải rộng 432px, chữ và ô nhập lớn hơn, nút cao 44px, thẻ nguồn/tập thoáng hơn.
- **Ô nhập Thể loại / Quốc gia**: hàng tìm kiếm cố định 44px, kính lúp luôn canh giữa cùng hàng với chữ
  (không còn bị đẩy xuống dòng).
- **Phim thủ công hiện trên app**: endpoint dailyUpdates (kệ *Phim Mới* khi app làm mới) nay cũng ghép
  phim admin thêm thủ công; trước đây chỉ home, list, search và detail mới ghép nên app làm mới là mất phim.

## 58. Phim mới lên đầu trang chủ, chi tiết theo tab, phụ đề trong PiP, tìm không dấu

- **Phim mới hiện ngay đầu trang chủ**: kệ *Phim Mới* luôn lấy danh sách sắp theo thời gian cập nhật
  (trước đây chỉ khi kéo làm mới mới dùng), cache máy chủ giảm từ 5 phút xuống 45 giây, và khi quay lại
  tab Trang chủ app tự nạp lại (ngưỡng chống nạp liên tục 60 giây → 15 giây). Phim admin thêm thủ công
  luôn nằm đầu vì được ghép trước kết quả API.
- **Chi tiết phim theo từng tab**: chi tiết phim được lưu theo slug thay vì một biến dùng chung, nên
  đang xem chi tiết phim A ở tab Tìm kiếm, sang tab Trang chủ mở phim B rồi quay lại vẫn đúng chi tiết
  phim A. Yêu cầu tải chi tiết cũng tách theo slug nên tab này không huỷ yêu cầu của tab kia.
- **Phụ đề trong PiP**: thêm endpoint `/api/cinema/subtitled.m3u8` sinh master playlist HLS version 4 có
  `EXT-X-MEDIA TYPE=SUBTITLES` trỏ tới file .vtt rời. Trình phát dùng playlist này khi tập có phụ đề rời,
  nên AVPlayerItem có nhóm phụ đề hợp lệ và PiP hiện được phụ đề; khi xem bình thường app vẫn vẽ phụ đề
  theo thiết lập của người dùng, chỉ chuyển sang phụ đề gốc lúc PiP bật. Nếu master playlist lỗi, trình
  phát tự quay về link M3U8 gốc ngay chứ không báo lỗi.
- **Tìm phim thủ công không dấu**: so khớp tên phim đã bỏ dấu tiếng Việt và hạ chữ thường, nên gõ
  "thuc tinh" tìm được "Thức Tỉnh", gõ "vision quest" tìm được "VisionQuest". Tìm kiếm theo API giữ nguyên.

## 59. Ngày tạo / ngày cập nhật trong Thêm phim thủ công

- **Ngày tạo** hiển thị theo `dd/mm/yyyy`: gõ số là tự chèn dấu "/", có nút lịch mở bộ chọn ngày của hệ
  điều hành. Giá trị lưu vẫn là `yyyy-mm-dd` nên phần gửi lên máy chủ không đổi.
- **Ngày cập nhật** bỏ phần giờ, chỉ còn `dd/mm/yyyy`, không cho sửa tay. Máy chủ tự dùng mốc cập nhật
  thật của bản ghi (`updatedAt`, tự đổi mỗi lần lưu) nên admin sửa phim xong là ngày đổi ngay: form nạp
  lại bản ghi vừa lưu, và app/web đều đọc mốc này thay cho cột `updatedDate` nhập tay trước đây.

## 60. Sửa lỗi build IPA

Năm lỗi biên dịch của vòng trước và cách xử lý:

- `subtitledPlaylistURL` bị chèn nhầm vào `TvVideo` (struct này không có `streamURL`/`directStreamURL`)
  do mẫu dò khớp vào struct đứng trước; đã chuyển về đúng `MovieEpisode`.
- `nativeSubtitleActive` được dùng nhưng chưa khai báo; đã thêm
  `@Published private(set) var nativeSubtitleActive = false` trong `PlaybackController`.
- `String.trim()` không tồn tại trong Swift; thay bằng
  `trimmingCharacters(in: .whitespacesAndNewlines)` (4 chỗ trong `CinemaStore`).
- Trình biên dịch quá thời gian suy luận biểu thức thân trình phát: tách `onChange(scenePhase)` thành
  `handleScenePhaseChange(_:)` và tách lớp phụ đề thành `subtitleOverlay(bottomInset:)`.
- Bỏ `detailRequestID` không còn dùng sau khi chi tiết phim chuyển sang quản lý theo slug.

## 61. Ngày tạo trên app, luồng lưu ở admin và trình cắt ảnh

- **App**: `formattedDate` chỉ đọc mốc ISO 8601 nên chuỗi `yyyy-MM-dd` của phim thêm thủ công bị hiện
  nguyên dạng `2026-10-14`. Nay phân tích thêm `yyyy-MM-dd`, `yyyy-MM-dd'T'HH:mm[:ss]` và `yyyy/MM/dd`
  nên mọi nơi trong trang chi tiết đều là `dd/MM/yyyy`.
- **Thông báo khi lưu**: chuyển từ dòng chữ nằm trong khung "Thông tin phim" thành **thông báo nổi** ở góc
  trên bên phải, tách hẳn khỏi form, tự ẩn sau 6 giây và tự xoá khi mở lại phim nên không còn hiện lại
  thông báo cũ. Thông báo có sẵn liên kết "Thêm nguồn & tập" tới phim vừa lưu và nút đóng.
- **Lưu xong là thoát form**: sau khi tạo hoặc lưu thay đổi, form tự làm mới đúng như khi bấm "+ Phim mới"
  (giữ 4 phần thông tin cho lần tạo sau), danh sách phim được nạp lại.
- **Trình cắt ảnh** viết lại: kéo ảnh để chọn vùng, 8 tay nắm đổi kích thước (khoá tỉ lệ theo khung đang
  chọn), phóng to 1–3x có dựng lại vùng chọn theo đúng tỉ lệ, thêm nút **Toàn bộ ảnh** (lấy trọn ảnh gốc,
  không cắt) và **Đặt lại**. Phép tính vùng cắt nay dựa trên vùng ảnh hiển thị thật nên ảnh cắt ra khớp
  đúng những gì đang thấy.

## 62. Phim thủ công không còn đứng đầu trang và nguồn riêng xem được trên web

**1. Phim thêm thủ công bị ghim ở đầu trang chủ**
`getHome` (và `getDailyUpdates`) ghép danh sách theo kiểu `[...custom, ...api]` nên phim admin thêm
**luôn** nằm trên cùng, mãi không chịu xuống dù sau đó có phim mới hơn từ API. Nay hai chỗ này trộn rồi
sắp theo mốc thời gian (`sortByFreshness`: ưu tiên `updatedAt`, sau đó `createdAt`), và `getMovies` dùng
chung tiện ích đó. Kết quả: phim vừa thêm vẫn nổi lên trên như mong muốn, nhưng khi có phim mới hơn thì
tự xuống đúng vị trí theo ngày cập nhật — cả trên web lẫn app vì thứ tự do máy chủ quyết định.

**2. Web báo "Nguồn phim đang được cập nhật" với nguồn admin thêm tay**
`registerStreamSource` chỉ chấp nhận host trong danh sách CDN của API (`kvp726.com`, `kkphimplayer*`,
`phim1280.tv`, `cdn-player.com`). Nguồn riêng của admin (ví dụ `v5.streamvsmov.com`) không thuộc danh
sách nên `streamUrl` và `directStreamUrl` đều `null` → web không có gì để phát. App vẫn xem được vì đọc
thẳng link M3U8 gốc.

Đã thêm hai hàm riêng cho nguồn do admin nhập:
- `registerCustomStreamSource`: nhận mọi host **https công khai** (không giới hạn danh sách CDN) và cấp
  token proxy — nhờ đó web xem được kể cả khi CDN không gửi header CORS.
- `customDirectStreamUrl`: trả link M3U8 gốc để trình phát thử trực tiếp trước, lỗi mới quay về proxy.

`mergeCustomSources` dùng hai hàm này cho cả tập lẫn từng mức chất lượng. Vẫn chặn host nội bộ/không
công khai (`localhost`, `127.*`, `10.*`, `192.168.*`, `172.16–31.*`, `169.254.*`, `.local`, IPv6 nội bộ)
và bắt buộc https để proxy không bị lợi dụng.

## 63. Phụ đề rời trên web + bảng tùy chỉnh phụ đề trong trình phát

**1. Web không hiện phụ đề của nguồn admin thêm tay**
Máy chủ đã trả `subtitleUrl` cho từng tập (route `/api/movies/subtitle/:id.vtt`, có CORS), nhưng phía web
thiếu hẳn phần đọc phụ đề: kiểu `Episode` không có trường phụ đề và `CinemaPlayer` không hề vẽ phụ đề.
Nay `Detail.tsx` khai báo `subtitleUrl`, truyền vào trình phát, và `canPlayEpisode` cũng tính cả nguồn
trực tiếp để tập có link M3U8 gốc vẫn phát được.

**2. Bộ đọc phụ đề trong trình phát web**
- `parseSubtitleFile` đọc cả WebVTT lẫn SRT (một số nguồn trả SRT dù đuôi `.vtt`), chấp nhận dấu phẩy
  thập phân, bỏ khối `NOTE`/`STYLE`, gỡ thẻ `<i>`, `{\an8}`, giải mã `&amp;`… và bỏ qua tệp rác.
- `findActiveCue` tìm nhị phân nên phụ đề dài (hàng nghìn cue) vẫn nhẹ.
- Lớp phụ đề tự vẽ (`cinema-subtitle-layer`) đồng bộ theo `timeupdate`/`seeked`, chỉ cập nhật state khi
  nội dung đổi để không re-render thừa.
- Trên iOS, trình phát hệ thống mở toàn màn hình nên không thể đè lớp riêng: thẻ `<track>` được giữ ở
  chế độ ẩn và tự chuyển sang hiện khi vào toàn màn hình hệ thống, nhờ đó phụ đề vẫn có.

**3. Bảng tùy chỉnh phụ đề (dùng được cả trong toàn màn hình)**
Nút CC trên thanh điều khiển mở bảng nằm **trong khung trình phát** — vì khung này chính là phần tử được
đưa lên toàn màn hình nên bảng và phụ đề vẫn hiện y như khi xem thường. Gồm các mục thường dùng nhất:
bật/tắt phụ đề, cỡ chữ (2.6–8% chiều cao khung hình nên toàn màn hình vẫn cân), màu chữ (5 màu nhanh +
bảng màu tự chọn), kiểu nền (viền chữ / hộp đen / trong suốt), vị trí (3–42% từ đáy), độ trễ ±0.5s, chữ
đậm, viền dày, và nút đặt lại mặc định. Mọi lựa chọn lưu vào `localStorage` nên nhớ cho lần xem sau.

## 64. Sửa lỗi "ngày cập nhật" tự nhảy dù admin không sửa gì

**Nguyên nhân gốc**
Cột `updatedAt` của bảng `custom_movies` được tạo với `ON UPDATE CURRENT_TIMESTAMP`. Trong khi đó hàm
`registerCustomMovieView()` chạy **mỗi lần có người mở trang chi tiết phim thủ công** (cả app lẫn web) và
chạy câu lệnh `UPDATE custom_movies SET viewCount = viewCount + 1 ...`. Vì câu lệnh này không gán
`updatedAt`, MySQL tự cập nhật cột đó thành thời điểm hiện tại — nên chỉ cần có người xem phim là "ngày
cập nhật" nhảy sang hôm nay, dù admin không sửa gì. Phụ phẩm kéo theo: thứ tự "phim mới cập nhật" ở
trang chủ cũng bị đổi theo lượt xem.

Đã kiểm chứng trên MySQL thật: cùng một bản ghi, câu lệnh cũ làm `updatedAt` nhảy từ `2026-10-14 09:00:00`
sang thời điểm chạy; câu lệnh mới giữ nguyên.

**Cách sửa (ba lớp bảo vệ)**
1. `registerCustomMovieView()` gán tường minh `updatedAt = updatedAt`, nên dù cột còn thuộc tính ON UPDATE
   thì lượt xem cũng không đổi ngày.
2. `ensureCustomMoviesCompatibility()` khi khởi động kiểm tra `INFORMATION_SCHEMA` và chạy một lần
   `ALTER TABLE custom_movies MODIFY COLUMN updatedAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP` để bỏ
   hẳn thuộc tính ON UPDATE trên hosting cũ.
3. Bỏ `.onUpdateNow()` khỏi schema và cho `updateCustomMovie()` tự gán `updatedAt: new Date()` — chỉ thao
   tác lưu của admin mới đổi ngày.

**Thêm: sửa nguồn/tập cũng tính là cập nhật phim**
`movieSources.ts` nay gọi `touchMovie()` khi admin thêm/đổi tên/xoá nguồn, thêm/sửa/xoá tập, hoặc sắp xếp
lại tập — vì đó là thao tác sửa phim thật. Lượt xem thì không.

## 65. Nút chỉnh phụ đề chỉ hiện với tập có phụ đề rời

Trước đây nút CC luôn hiện trên thanh điều khiển của mọi tập; bấm vào với tập không có phụ đề thì bảng chỉ
báo "Tập này không có phụ đề rời" — vừa thừa vừa gây hiểu nhầm là phụ đề đang lỗi.

Nay nút CC (và cả bảng tùy chỉnh) **chỉ xuất hiện khi tập đang phát thật sự có phụ đề rời** (trường
`subtitleUrl`), tức các tập thuộc nguồn admin thêm tay có kèm phụ đề. Phim lấy từ API không có phụ đề rời
thì thanh điều khiển gọn như cũ, không còn nút thừa.

Kèm theo: khi đổi tập, bảng chỉnh phụ đề tự đóng để không bật lại ngoài ý muốn ở tập kế tiếp.

## 66. Ba sửa lỗi: thông báo trên app, thêm thể loại/quốc gia riêng, form còn sót dữ liệu

**1. App — thẻ "Đề xuất hôm nay" che thông báo "Có phim mới"**
Thẻ đề xuất ở đầu trang chủ được đẩy lên theo hiệu ứng parallax (`offset(y: -pull * 0.30)`), nên nó vẽ đè
lên thông báo nằm ngay trên nó. Thông báo nay được nâng lên lớp trên bằng `.zIndex(1)` nên luôn đọc được,
và tự ẩn sau 8 giây để không nằm lại chắn nội dung khi lướt xuống.

**2. Web — thêm thể loại và quốc gia ngoài danh sách API**
Ô Thể loại và Quốc gia trong trang thêm/sửa phim thủ công nay cho phép admin gõ tên rồi **ấn Enter** để
thêm mục riêng (ví dụ "Phim Nhạc"). Khi chữ đã gõ chưa trùng lựa chọn nào, một nút `+ Thêm "…"` hiện ngay
trong thanh công cụ và dòng gợi ý đổi thành "Chưa có trong danh sách — ấn Enter để thêm". Mục tự thêm nằm
chung trong danh sách đã chọn ở trên, bỏ chọn được như mục có sẵn. Nếu tên gõ trùng một mục có sẵn thì hệ
thống chọn luôn mục đó thay vì tạo bản trùng.

**3. Web — tạo phim xong mà form vẫn còn dữ liệu phim cũ**
Bản trước lưu 4 phần thông tin vào `localStorage` rồi nạp lại sau khi tạo phim, nên F5 hay bấm "Phim mới"
vẫn thấy nguyên dữ liệu phim vừa lưu (ví dụ Klute). Nay bỏ hẳn việc đọc/ghi nháp: vào trang là form trắng,
lưu xong cũng trắng, và bản nháp cũ còn sót trong trình duyệt được dọn tự động.

## 67. Lọc "Phim Thuyết Minh" / "Phim Vietsub" trả về đúng phim thủ công

**Nguyên nhân.** Trong `customMoviesForFilter`, mọi kiểu lọc không nằm trong nhóm đã xử lý riêng
(`single`, `series`, `shows`, `ongoing`, `completed`) đều được coi là hợp lệ, kèm chú thích "phim thủ công
luôn được coi là hợp lệ". Vì `vietsub`/`thuyetminh`/`longtieng` rơi vào nhánh này, phim thêm thủ công xuất
hiện ở **mọi** danh sách theo nguồn — kể cả khi nguồn của nó chỉ là Vietsub.

**Cách sửa.** Thêm phép so khớp kiểu nguồn dựa trên tên nguồn thật của phim:

- `movieSources.listSourceNamesBySlug()` đọc tên nguồn của tất cả phim thủ công trong **một** truy vấn,
  chỉ gọi khi bộ lọc thật sự cần (không tốn thêm truy vấn cho các lần lọc khác).
- `sourceNameMatchesAudioKind(name, kind)` bỏ dấu tiếng Việt rồi so khớp: Vietsub khớp `vietsub`, `viet sub`,
  `phụ đề`, `sub việt`; Thuyết minh khớp `thuyết minh` hoặc token `TM`; Lồng tiếng khớp `lồng tiếng` hoặc
  token `LT`.
- Phim thủ công chỉ vào danh sách Vietsub/Thuyết minh/Lồng tiếng khi **có ít nhất một nguồn đúng kiểu đó**.
  Các bộ lọc khác (Mới cập nhật, Phim bộ, Phim lẻ, Đang chiếu…) giữ nguyên hành vi cũ.

**Kiểm chứng.** Chạy 14 trường hợp tên nguồn thực tế qua hàm so khớp: `Vietsub` khớp `vietsub` và **không**
khớp `thuyetminh`; `Thuyết minh`/`TM` khớp `thuyetminh`; `Lồng tiếng`/`LT` khớp `longtieng`; nguồn chung
chung như `Nguồn 1` không lọt vào danh sách nào. Sửa ở tầng máy chủ nên **cả web và app** đều đúng.

## 68. Ngôn ngữ có lựa chọn nhanh, lịch chọn ngày mới, lấy diễn viên & đạo diễn theo TMDB/IMDB ID

**1. Ngôn ngữ (web).** Mục Ngôn ngữ từ ô nhập tự do thành danh sách chọn: *Vietsub*, *Thuyết minh*,
*Lồng tiếng* và *Khác…*. Chọn *Khác…* thì hiện thêm ô nhập tự do (ví dụ "Vietsub AI") kèm dòng nhắc rằng
phim vẫn nằm đúng danh sách lọc. Về phía máy chủ, `customMoviesForFilter` nay so khớp **cả ngôn ngữ của
phim** lẫn tên nguồn, nên "Vietsub AI" vẫn được tính là Vietsub khi lọc.

**2. Lịch chọn ngày (web).** Ô Ngày tạo thay lịch mặc định của hệ điều hành (khó bấm ra, phải chọc đúng
biểu tượng nhỏ) bằng lịch riêng mở ngay dưới ô nhập: nút lùi/tiến tháng, ô chọn tháng, ô nhập năm để nhảy
nhanh, lưới ngày kiểu Việt Nam (thứ Hai đầu tuần), đánh dấu ngày đang chọn và ngày hôm nay, kèm nút
*Hôm nay* và *Xoá ngày*. Lịch đóng khi bấm ra ngoài hoặc ấn Esc, có hiệu ứng mở nhẹ. Vẫn gõ tay dd/mm/yyyy
được như trước và giá trị gửi lên máy chủ không đổi.

**3. Lấy diễn viên & đạo diễn theo TMDB/IMDB ID (web).** Thêm nút *Lấy từ TMDB/IMDB* ở mục 04. Dịch vụ mới
`server/movieCredits.ts` dùng TMDB ID để gọi `movie/{id}/credits`, tự chuyển sang nhánh `tv/{id}/credits`
cho phim bộ (lấy thêm `created_by` làm đạo diễn); nếu chỉ có IMDB ID thì tra qua `find/{id}` để đổi sang
TMDB ID trước. Trả về tên phim, danh sách đạo diễn và diễn viên kèm ảnh; trang quản trị ghép vào form và
bỏ qua người đã có. Kết quả nhớ tạm 10 phút. Nếu hosting không gọi được TMDB thì nút tự lấy từ trình duyệt
(TMDB mở CORS) và báo rõ cho admin.

**Kiểm chứng.** `fetchMovieCredits` chạy thật với 4 mã: TMDB `550` và IMDB `tt0137523` đều ra "Sàn Đấu Sinh
Tử" + David Fincher + 6 diễn viên kèm ảnh; TMDB `1399` và IMDB `tt0903747` ra phim bộ với `created_by` làm
đạo diễn. Bộ so khớp ngôn ngữ đúng 7/7 trường hợp, `tsc` sạch, `npm run build` và 14 test đều đạt.

## 69. Sửa lỗi build trên hosting: gói backend kèm sẵn `dist`, khoá rollup theo nền tảng

**Hiện tượng.** Chạy `npm install --include=dev && npm run build` trên cPanel báo:

```text
Error: Cannot find module @rollup/rollup-linux-x64-gnu
    at requireWithFriendlyError (.../nodevenv/cinemora2/22/lib/node_modules/rollup/dist/native.js:121:9)
```

Nguyên nhân là lỗi nổi tiếng của npm với dependency tuỳ chọn (npm/cli#4828): `vite` cần gói nhị
phân `@rollup/rollup-linux-x64-gnu` nhưng npm bỏ qua khi cài từ lockfile, rồi Node vớ phải bản
`rollup` toàn cục trong nodevenv — bản này không có file `.node` cho Linux. Vì `dist` bị xoá
trước khi build nên ứng dụng dừng luôn.

**Ba thay đổi để không còn gặp lại:**

1. **Gói backend kèm sẵn `dist/`** (`dist/index.js` + `dist/public/`) — bản đã dựng trong lúc đóng
   gói. Trên hosting chỉ cần `npm install --omit=dev --legacy-peer-deps` rồi Restart, **không cần
   `npm run build`** nên không còn phụ thuộc `vite`/`rollup`.
2. **Khai báo rõ gói nhị phân rollup** trong `optionalDependencies` của `package.json` và
   `package-lock.json` (`@rollup/rollup-linux-x64-gnu`, `…-musl`, `…-arm64-gnu`) để nếu admin vẫn
   muốn build tại chỗ thì npm luôn cài đúng gói cho Linux.
3. **Tài liệu `DEPLOY-CPANEL-VI.md`**: quy trình mới không build, kèm mục *Sự cố thường gặp* giải
   thích cảnh báo `export: '=43e64c…': not a valid identifier` (biến `TMDB_API_KEY` bị khai báo
   thiếu tên trong cPanel) và cách sửa — khai lại đúng Name/Value hoặc tạo tệp `.env`, vì server
   đã nạp `.env` bằng `dotenv/config`.

**Kiểm chứng.** Trong gói: `dist/index.js` chứa `fetchMovieCredits` và phần lọc theo ngôn ngữ phim;
JS/CSS của website chứa nút *Lấy từ TMDB/IMDB*, danh sách Ngôn ngữ, lịch chọn ngày và lời gọi
route `fetchCredits`. `npm install --dry-run` chạy sạch với lockfile mới.

## 70. Sửa danh sách Ngôn ngữ, lịch chọn ngày và nút lấy diễn viên/đạo diễn

**1. Danh sách Ngôn ngữ nhảy về "Chưa chọn".** Khi chọn *Khác…*, giá trị ô chọn được tính lại từ
chuỗi ngôn ngữ đang trống nên rơi về "Chưa chọn", dù ô nhập tự do đã hiện. Nay trạng thái "đang chọn
Khác" được ghi nhớ riêng (`langOther`) và dùng làm giá trị của ô chọn, nên chọn *Khác…* là danh sách
giữ đúng *Khác…*; mở lại phim đã lưu có ngôn ngữ tự do cũng tự bật đúng trạng thái này.

**2. Giao diện chọn tháng của lịch.** Ô Ngày tạo trước đây dùng `<select>` của hệ điều hành nên bấm
vào hiện một danh sách dài, lệch khỏi khung và che cả form. Nay tên tháng là một nút trong đầu lịch;
bấm vào sẽ mở lưới 12 tháng (T1–T12) gọn trong khung lịch, tháng đang xem được tô vàng, chọn xong
quay lại lưới ngày ngay. Nút lùi/tiến tháng, ô nhập năm, nút *Hôm nay* / *Xoá ngày* giữ nguyên.

**3. Nút "Lấy từ TMDB/IMDB" không rõ vì sao không thêm ai.** Thông báo cũ chỉ nói "Không có gì mới để
thêm" nên không biết TMDB không trả về gì hay mọi người đã có sẵn. Nay:

- Luôn thử qua máy chủ trước, chỉ khi máy chủ lỗi mới gọi từ trình duyệt (trước đây dựa vào cờ
  "máy chủ không gọi được" của phần tìm diễn viên nên có thể đi sai đường).
- Thông báo nêu rõ số lượng: *"Đã thêm 12 diễn viên và 1 đạo diễn từ TMDB cho phim … (TMDB trả về
  12 diễn viên và 1 đạo diễn)"*, hoặc *"TMDB trả về 12 diễn viên và 1 đạo diễn, nhưng tất cả đã có
  trong danh sách nên không thêm gì."*, hoặc *"TMDB không trả về diễn viên hay đạo diễn nào cho mã
  đã nhập."*
- Khi cả hai phía đều lỗi thì báo gộp: *"Máy chủ: … · Trình duyệt: …"* (đọc được cả lỗi tRPC dạng
  object), nhờ đó biết ngay là thiếu khoá TMDB, sai mã phim, hay máy chủ chưa có route mới.

**4. Kèm sẵn khoá TMDB cho máy chủ.** Gói backend nay có tệp `.env` chứa `TMDB_API_KEY` để sau khi
giải nén là máy chủ gọi được TMDB ngay, không phụ thuộc biến môi trường cấu hình sai trong cPanel.
`dotenv` không ghi đè biến đã có nên nếu cPanel đã đặt đúng thì vẫn giữ giá trị cũ. `.env` nằm trong
`.gitignore` nên không đi lên GitHub.

## 71. Sửa gốc lỗi "TMDB trả về 2 diễn viên nhưng không thêm gì" và đổi danh sách Ngôn ngữ

**1. Vì sao TMDB trả về diễn viên mà không thêm được ai.** Hàm so trùng tên cũ rút gọn tên bằng
`.replace(/[^a-z0-9]/g, "")` — chỉ giữ chữ Latin. Tên chữ Hán/Hàn/Nhật bị rút thành chuỗi rỗng, nên
mọi diễn viên loại này đều bị coi là "đã có trong danh sách" và bị bỏ qua, dù danh sách đang trống.
Nay hàm chỉ bỏ khoảng trắng và dấu câu, **giữ chữ của mọi hệ chữ**, thêm cả xử lý `đ/Đ`:

- `章子怡` → `章子怡` (trước đây → rỗng)
- `장혁` → `장혁` (trước đây → rỗng)
- `Trần Bảo Sơn` → `tranbaoson`, `Lee Min-ho` → `leeminho` (giữ nguyên như cũ)

Thêm nữa, nếu tên không rút gọn được thì lấy chính tên gốc làm khoá, và chỉ bỏ qua khi tên trống hẳn
— nên không còn trường hợp "trùng với chính chuỗi rỗng".

**2. Danh sách Ngôn ngữ.** Ô chọn cũ là `<select>` của hệ điều hành nên bấm vào hiện bảng xanh mặc
định của trình duyệt, lệch hẳn tông giao diện. Nay thay bằng danh sách tự vẽ: nút hiện ngôn ngữ đang
chọn, bấm mở bảng nền tối đúng tông web, mục đang chọn được tô vàng kèm dấu ✓, chọn xong tự đóng,
bấm ra ngoài hoặc Esc cũng đóng. Chọn *Khác…* vẫn mở ô nhập tự do như trước và giữ nguyên chữ đã gõ.

## 72. Lấy đủ diễn viên và đạo diễn từ TMDB

**1. Chọn đúng nhánh phim lẻ / phim bộ.** Mã số TMDB tồn tại ở cả hai nhánh `movie` và `tv`, nên
nhập mã của một phim bộ có thể lấy nhầm một phim lẻ khác trùng số — đúng hiện tượng "TMDB trả về 2
diễn viên và 0 đạo diễn". Nay nút gửi kèm *Loại phim* và *Tên phim* của form: phim bộ ưu tiên nhánh
TV, phim lẻ ưu tiên nhánh movie; đồng thời đọc cả hai nhánh rồi chọn bản có tiêu đề khớp với tên
phim đã nhập (trùng hẳn 3 điểm, chứa nhau 2 điểm). Tiêu đề TMDB trả về vẫn hiện trong thông báo nên
nếu chọn nhầm là thấy ngay.

**2. Lấy nhiều người hơn.** Trước đây cắt còn 12 diễn viên; nay lấy 30 (trần 60) cho cả đường máy
chủ lẫn đường dự phòng từ trình duyệt.

**3. Đạo diễn của phim bộ.** Ngoài job `Director`, nay nhận thêm job `Creator` trong crew và danh
sách `created_by` của TMDB — nhờ đó phim bộ không còn trắng ô Đạo diễn.

**4. Tên diễn viên.** Nếu TMDB thiếu `name` thì lấy `original_name`, tránh bỏ sót người.

**5. Báo đúng lỗi khi thiếu khoá.** Trước đây mọi lỗi gọi TMDB đều bị nuốt và hiện thành "TMDB không
có dữ liệu diễn viên". Nay lỗi thật (thiếu `TMDB_API_KEY`, mạng không ra ngoài…) được giữ lại và
hiển thị nguyên văn. Gói backend cũng đã kèm `.env` chứa khoá TMDB nên máy chủ có khoá ngay.

**Kết quả kiểm chứng thật:** mã 550 (Fight Club) → 30 diễn viên, đạo diễn David Fincher; mã 1399
(Game of Thrones, khai phim bộ) → 14 diễn viên, 3 đạo diễn gồm cả người tạo phim.

## 73. Phim bộ: lấy đủ diễn viên như trên web TMDB

**Vì sao "Between Steps" chỉ ra 2 diễn viên.** TMDB có hai endpoint cho phim bộ:

- `/tv/{id}/credits` → chỉ vài người ghi ở cấp phim (phim mới lên sóng thường đúng 2).
- `/tv/{id}/aggregate_credits` → gom diễn viên của **mọi mùa**, đúng bằng danh sách trên web TMDB.

Bản cũ chỉ gọi đường thứ nhất nên ra 2 người. Nay với phim bộ, hệ thống đọc cả hai đường và giữ bản
nhiều diễn viên nhất; phim lẻ vẫn dùng `/movie/{id}/credits` (vốn đã đầy đủ).

**Tên diễn viên.** Credits nay đọc với `language=en-US` nên tên người Hàn/Trung/Nhật hiện ở dạng
Latin (`Choo Young-woo`, `Kim So-hyun`…) thay vì chữ bản địa; tiêu đề phim vẫn lấy theo tiếng Việt.

**Đạo diễn phim bộ.** `aggregate_credits` gom đạo diễn của từng tập nên danh sách rất dài (Game of
Thrones có 20 người). Nay cân theo `total_episode_count`, đưa người tạo phim (`created_by`) lên đầu
và chỉ giữ **6 người chính**; dạng crew của aggregate cũng dùng mảng `jobs` nên đã đọc đúng cả hai
dạng dữ liệu.

**Kết quả kiểm chứng thật:**

| Nhập | Trước | Sau |
|---|---|---|
| Between Steps (307106, phim bộ) | 2 diễn viên, 0 đạo diễn | **17 diễn viên** (đúng bằng web TMDB) + đạo diễn Ahn Pan-seok |
| Game of Thrones (1399, phim bộ) | 14 diễn viên, 20 đạo diễn | **30 diễn viên**, 6 đạo diễn (D. B. Weiss, David Benioff, …) |
| Fight Club (550, phim lẻ) | 12 diễn viên | **30 diễn viên** + David Fincher |

## 74. Chọn đúng nhánh khi mã TMDB trùng giữa phim lẻ và phim bộ

**Hiện tượng.** Nhập mã **16346** (Center Stage: Turn It Up, 21 diễn viên, 1 đạo diễn) nhưng hệ thống
báo đã thêm 1 diễn viên cho phim **"Game Show in My Head"**. Tra thẳng TMDB thì thấy mã 16346 tồn tại
ở cả hai nhánh:

| Nhánh | Tiêu đề | Diễn viên |
|---|---|---|
| `movie/16346` | Center Stage: Turn It Up | **21** |
| `tv/16346` | Game Show in My Head | **1** |

Bản cũ chỉ dựa vào ô *Loại phim* của form, nên khi form để "Phim bộ" mà ô *Tên phim* còn trống thì
lấy nhánh phim bộ và chỉ ra 1 diễn viên.

**Cách sửa.**

1. Tiêu đề dùng để đối chiếu nay lấy bản **tiếng Anh** (trước lấy tiếng Việt nên tên quốc tế như
   "Fight Club" không khớp với "Sàn Đấu Sinh Tử").
2. Khi tên phim trống, hoặc không khớp cả hai nhánh, hệ thống chọn nhánh **đầy đủ dữ liệu hơn hẳn**
   (nhiều diễn viên gấp 3 lần và từ 5 người trở lên) — đúng trường hợp 1 so với 21.
3. Thứ tự ưu tiên theo *Loại phim* vẫn được giữ khi hai nhánh tương đương nhau.

**Kết quả kiểm chứng thật:**

| Nhập | Sau khi sửa |
|---|---|
| 16346, tên trống, khai phim bộ | **Center Stage: Turn It Up — 21 diễn viên, đạo diễn Steven Jacobson** |
| 16346, tên đúng, khai phim bộ | Center Stage: Turn It Up — 21 diễn viên |
| 550 Fight Club, khai nhầm phim bộ | Fight Club — 30 diễn viên, David Fincher |
| 1399 Game of Thrones, phim bộ | Game of Thrones — 30 diễn viên, 6 đạo diễn |
| 307106 Between Steps, phim bộ | Between Steps — 17 diễn viên, đạo diễn Ahn Pan-seok |

## 75. Sửa lỗi app "không thể phát video"

**Nguyên nhân.** App ưu tiên phát thẳng link M3U8 của CDN ngoài, trong khi website phát qua proxy của
máy chủ. Các CDN này chặn client không phải trình duyệt, nên chỉ cần CDN đổi cách kiểm tra là app
không phát được phim nào — đúng hiện tượng "vô xem phim báo không thể phát video". Kiểm tra trực tiếp
trên máy chủ thật cho thấy proxy của Cinemora chạy đủ cả ba bước:

| Bước | Kết quả |
|---|---|
| Master playlist `/api/cinema/stream/<token>` | 200 · `application/vnd.apple.mpegurl` |
| Playlist tập (variant) | 200 · 64 KB danh sách phân đoạn |
| Phân đoạn video | 200 · `video/mp2t` |

**Cách sửa.**

1. `playbackURL` của tập phim nay **ưu tiên link proxy** của Cinemora, link CDN gốc chỉ là phương án
   sau — đúng đường mà website đang phát được.
2. Đường phát kèm phụ đề rời (`subtitledPlaylistURL`) cũng dùng link proxy, và nhận diện được link
   proxy nên PiP vẫn có nhóm phụ đề hợp lệ.
3. Route `/api/cinema/subtitled.m3u8` trước yêu cầu link video phải chứa `.m3u8`, nên khi app truyền
   link proxy (không có đuôi này) máy chủ trả 400. Nay route chấp nhận cả hai dạng.

**Lưu ý khi cập nhật.** Sửa ở cả hai phía nên cần cập nhật **cả backend lẫn app**: backend để route
phụ đề nhận link proxy, app để phát qua proxy. Nếu chỉ cập nhật một phía, phim có phụ đề rời vẫn lỗi.

## 76. Lọc theo kiểu nguồn và giữ vị trí trang khi quay lại

**1. Phim Vietsub lọt vào danh sách Thuyết minh.** Bộ lọc gửi lên hai dạng: chọn **một** mục thì app
gửi `kind` (số ít — "Phim Thuyết Minh", "Phim Vietsub"…), chọn **nhiều** mục thì gửi `kinds` (mảng).
Đoạn gộp phim thủ công vào danh sách chỉ đọc `kinds`, nên khi chọn một mục thì danh sách kiểu nguồn
rỗng và phim thủ công **bỏ qua hẳn** bước kiểm tra — vietsub hiện trong thuyết minh.

Nay hai dạng được gộp lại trước khi lọc. Bảng đối chiếu tên nguồn cũng đã kiểm chứng:

| Tên nguồn | Lọc theo | Kết quả |
|---|---|---|
| Vietsub | thuyết minh | loại — đúng |
| Vietsub / Vietsub AI | vietsub | nhận — đúng |
| Thuyết Minh / TM | thuyết minh | nhận — đúng |
| Lồng Tiếng | vietsub | loại — đúng |

**2. Xem phim xong quay lại bị về trang 1.** Mục Khám phá ghi nhớ "lần nạp trước" và tự nạp lại khi
dữ liệu cũ quá 3 phút. Lần nạp đó xoá lưới và bắt đầu lại từ trang 1, nên đang xem ở trang 3 mà mở
một phim rồi quay lại là mất vị trí.

Nay nếu người dùng đang ở trang sâu (từ trang 2 trở đi) thì lần quay lại **giữ nguyên lưới và vị trí**,
không tự nạp lại. Việc tự làm mới vẫn giữ cho trang 1, nơi không mất gì.

## 77. Web: tua phim đang xem dở bị kéo về đoạn cũ

**Hiện tượng.** Vào mục Thư viện → "Bạn đang xem dở", mở lại một phim và tua thì phim cứ nhảy về đúng
đoạn đang xem dở; phải F5 trang mới tua được.

**Nguyên nhân.** Trình phát áp vị trí xem dở trong sự kiện `canplay`:

```tsx
const seekTo = startAtRef.current;
if (seekTo && seekTo > 5 && Math.abs(v.currentTime - seekTo) > 2) {
  v.currentTime = seekTo;
}
```

`canplay` không chỉ bật một lần khi tải nguồn: trình duyệt bật lại sự kiện này **sau mỗi lần tua** và
sau mỗi lần đệm xong. Vì điều kiện chỉ so khoảng cách với vị trí cũ, mỗi lần người xem tua đi quá 2
giây là trình phát lập tức kéo về đoạn cũ. Tải lại trang thì vị trí xem dở đã bằng đúng chỗ đang xem
nên không còn bị kéo nữa — đúng như bạn thấy.

**Cách sửa.** Vị trí xem dở giờ chỉ được áp **một lần cho mỗi lần nạp nguồn**, qua cờ
`resumeSeekAppliedRef`:

1. Đặt lại cờ khi nạp nguồn mới (đổi tập, đổi nguồn, đổi chất lượng) — resume vẫn hoạt động như cũ.
2. Trong `canplay`, chỉ tua khi cờ chưa bật.
3. Ngay khi người xem tự tua (`seeking`), bật cờ khoá — vị trí xem dở không bao giờ kéo ngược lại nữa.

Nhờ vậy: mở phim từ "Bạn đang xem dở" vẫn vào đúng đoạn cũ, nhưng tua là ăn ngay, không cần F5.

## 78. Dán danh sách nhiều tập cho một nguồn

Trang **Quản lý nguồn & tập phim** → nguồn thêm thủ công → khối "Thêm tập mới" nay có thêm nút
**"Dán danh sách nhiều tập"**. Chuyển sang chế độ đó, admin dán hàng chục tập một lượt theo mẫu:

```
Tập 01|https://v8.streamvsmov.com/video/…/master.m3u8|https://…/vie.vtt
Tập 02|https://v8.streamvsmov.com/video/…/master.m3u8
https://v8.streamvsmov.com/video/…/master.m3u8        ← bỏ tên, hệ thống tự đánh số
```

- Mỗi dòng một tập, ba cột ngăn bằng dấu `|` (nhận cả dấu Tab): **tên tập | link M3U8 | link sub**.
  Cột phụ đề bỏ trống được; bỏ trống tên tập thì hệ thống tự đánh "Tập 01, Tập 02…".
  Dòng trống và dòng bắt đầu bằng `#` được bỏ qua.

**Kiểm tra một lượt khi bấm Thêm tập.** Toàn bộ danh sách được đọc và đối chiếu ngay khi dán, hiện
thành bảng có số dòng:

| Trường hợp | Kết quả |
|---|---|
| Trùng link M3U8 với tập đã có | dòng bôi đỏ, báo "Trùng link M3U8 với tập đã có" |
| Trùng tên tập với tập đã có | dòng bôi đỏ, báo "Trùng tên tập với tập đã có" |
| Trùng ngay trong danh sách vừa dán | dòng sau bị bôi đỏ |
| Thiếu cột link M3U8 | dòng bôi đỏ, báo thiếu link |
| Link không phải http/https | dòng bôi đỏ, báo sai định dạng |

Khi bấm **Thêm … tập**, trang tự **cuộn tới đúng dòng lỗi đầu tiên**. Các dòng hợp lệ được thêm trong
**một lần gọi máy chủ** (`movieSources.addEpisodes`) nên dán 100 tập vẫn nhanh, không bấm từng tập.
Những dòng lỗi/trùng được **giữ lại trong ô nhập** để admin sửa rồi gửi tiếp.

Máy chủ kiểm tra lại lần nữa trước khi ghi: bỏ qua dòng trùng tên hoặc trùng link đã có trong nguồn và
trả về số tập đã thêm kèm danh sách bị bỏ qua, nên kể cả hai tab cùng thao tác cũng không sinh tập trùng.
Thêm tập hàng loạt vẫn đánh dấu ngày cập nhật của phim như thao tác thủ công.

## 79. Ô dán danh sách tập có mặt ở cả trang phim thủ công

Khối **Nguồn & tập** trong trang *Thêm / chỉnh sửa phim thủ công* nay có nút **"Dán danh sách nhiều tập"**
ngay trên ô "Thêm tập mới". Bấm vào là đổi sang ô dán danh sách, dán bao nhiêu tập cũng được trong một
lượt, đúng định dạng `tên tập | link m3u8 | link sub (nếu có)`.

Toàn bộ phần đọc – kiểm tra – bôi đỏ – cuộn tới dòng lỗi – gửi một lần được tách thành thành phần dùng
chung `client/src/components/BulkEpisodesInput.tsx`, nên hai nơi dùng chung một cách xử lý:

| Nơi dùng | Đường dẫn |
|---|---|
| Quản lý nguồn & tập phim | `/admin/movies/sources?slug=…` |
| Nguồn & tập trong phim thủ công | `/admin/movies/custom/...` |

Sửa định dạng hay cách báo lỗi ở thành phần dùng chung là cả hai trang cập nhật theo, không lệch nhau.
Khi đang ở chế độ dán danh sách, nút **"Nhập từng tập"** đưa về lại ô nhập một tập kèm chất lượng và
phụ đề upload như trước; chế độ sửa tập vẫn giữ nguyên form một tập.

## 80. Danh sách tập gọn trong khung có thanh cuộn

Trước đây nguồn có nhiều tập thì danh sách kéo dài hết trang, cuộn chuột rất mỏi. Nay khối tập của mỗi
nguồn nằm trong một khung cao tối đa 336px, tự xuất hiện thanh cuộn khi vượt:

- Áp dụng cho cả hai nơi: **Quản lý nguồn & tập phim** và khối **Nguồn & tập** trong trang phim thủ công
  (cùng dùng lớp `.admin-episode-list`).
- Nguồn ít tập thì khung tự co lại đúng số tập, không có thanh cuộn thừa.
- Cuộn trong khung không kéo theo cả trang (`overscroll-behavior: contain`) nên lăn chuột tới cuối danh
  sách không làm nhảy trang.
- Thanh cuộn được tô theo tông giao diện (mảnh, màu vàng chanh mờ) thay vì thanh xám mặc định của trình
  duyệt.
- Bấm **Sửa** một tập thì trang tự cuộn nhẹ để hàng đang mở form nằm trong tầm nhìn, không bị khuất trong
  khung.

## 81. Nhãn hiển thị nhiều lớp, kiểu tên nổi bật, ảnh đại diện và giờ bình luận

**Thời gian bình luận không còn "vừa xong" mãi.** Máy chủ đọc `UNIX_TIMESTAMP(createdAt)`
để lấy thời điểm tuyệt đối thay vì tin vào múi giờ của MySQL, nên `createdAt` gửi cho app
luôn đúng. Trên app, danh sách bình luận có thêm nhịp 30 giây tự cập nhật nhãn thời gian
("vừa xong", "3 giờ", "2 ngày") nên để app mở lâu vẫn đúng.

**Nhiều nhãn cho một tài khoản.** Cột `users.badges` lưu mảng JSON (tối đa 6 nhãn), mỗi nhãn:
- *Chữ*: nội dung, màu chữ, màu nền, kiểu (đặc, chuyển sắc, viền, phát sáng, loé sáng, nhấp nháy),
  font (không chân, có chân, đều, viết tay), kích thước (nhỏ, vừa, lớn), hiệu ứng chuyển động
  (nhịp nhàng, loé sáng, bồng bềnh).
- *Ảnh / GIF*: dán link hoặc tải tệp lên. Trên app ảnh cao **18pt**, rộng tối đa **64pt**
  (làm ảnh cao 54–72px để nét trên màn hình Retina, dung lượng dưới 300KB; GIF nên dán link
  để giữ chuyển động).

**Làm nổi bật tên người dùng.** Cột `users.nameStyle` lưu màu và hiệu ứng tên: phát sáng,
chuyển sắc, loé sáng, cầu vồng, viền chữ. Quản trị viên vẫn mặc định có tên xanh nổi bật và
tích xanh động như trước; kiểu riêng đặt trên web sẽ thắng kiểu mặc định.

**Quản lý ảnh đại diện.** Trang *Quản lý tài khoản* xem được ảnh lớn, tải ảnh mới lên (tự cắt
vuông giữa ảnh rồi thu về 256px trước khi lưu), dán link, hoặc xoá ảnh đại diện. Mọi thay đổi
phát tín hiệu làm mới nên app thấy ngay.

**Đồng bộ tức thì.** Mọi thao tác đổi nhãn, đổi kiểu tên, đổi/xoá ảnh đại diện đều gọi
`publishAllComments()`: bình luận **cũ** của người đó cũng hiện nhãn mới ngay, không phải
bình luận lại.

**Giao diện web.** Trình soạn nhãn nằm trong mục *Sửa* của từng tài khoản: chọn Chữ / Ảnh-GIF,
xem trước ngay cạnh tên, gợi ý nhanh VIP · MOD · Kim cương. Danh sách bình luận trong trang
*Quản lý phim* hiện đủ nhiều nhãn và tên nổi bật đúng như trên app.

## 82. Sửa màn hình trắng khi quay lại danh sách "Xem thêm" và làm lại bố cục sửa tài khoản

**Màn hình trắng sau khi xem chi tiết phim.** Trang chủ → *Xem thêm* một mục (ví dụ Phim
Bộ) → mở một phim → *Trở lại*: cả danh sách biến mất, chỉ còn nút "Trở lại" và thanh tab.

Nguyên nhân: hiệu ứng vào của mỗi ô do `AuroraReveal` điều khiển, và nó bắt đầu ở
`opacity(0)` rồi bật lên trong `onAppear`. Lưới lười (`LazyVStack`/`LazyVGrid`) dựng lại các
ô khi màn hình bị che rồi hiện lại — nhưng lần dựng lại đó `onAppear` có thể không chạy, nên
trạng thái kẹt ở "chưa hiện" và cả danh sách trong suốt vĩnh viễn.

Cách sửa: `AuroraReveal` **không còn dùng độ mờ làm điểm bắt đầu**. Chuyển động vào giờ chỉ
dùng độ dời 10pt và tỉ lệ 0.985 → 1, nên dù animation có chạy hay không thì nội dung vẫn
luôn đọc được. Kèm theo, `SectionListScreen` tự nạp lại danh sách nếu tỉnh dậy với danh sách
rỗng, nên không còn trường hợp màn trắng.

**Bố cục lại phần "Chỉnh sửa thông tin tài khoản"** trên web admin:
- Đầu bảng có khối nhận diện: ảnh đại diện, tên kèm nhãn, email · ID · quyền, và nút đóng.
- Chia hai cột: cột trái là *01 Thông tin tài khoản* và *02 Ảnh đại diện*; cột phải là
  *03 Nhãn hiển thị* và *04 Làm nổi bật tên*. Dưới 1080px tự gộp về một cột.
- Mỗi nhóm là một thẻ riêng, có số thứ tự, tiêu đề, mô tả ngắn và hàng nút lưu riêng.
- Ô nhập có nhãn phía trên, gợi ý nhỏ bên dưới, viền sáng khi focus; bộ đếm `x/6 nhãn` cạnh
  nút *Thêm nhãn*.
- Hàng ảnh đại diện xếp thành lưới 92px + phần thao tác, không còn tràn ra ngoài thẻ.

## 83. Sửa lỗi build IPA: khai báo lại `Color(hex:)` và `.italic(_:)`

Hai lỗi biên dịch trong `Design/CommentBadges.swift`:

- **`invalid redeclaration of 'init(hex:)'`** — `State/SubtitlePreferences.swift` đã có
  `Color.init(hex:)`; bản thêm cho nhãn hiển thị dùng cùng tham số nên bị coi là khai báo
  lại. Đổi tên bản mới thành `Color.init?(cssHex:)` và cập nhật ba chỗ gọi trong
  `CommentBadges.swift`. Phần phụ đề giữ nguyên `Color(hex:)` cũ.
- **`'italic' is only available in iOS 26.0 or newer`** — `.italic(badge.font == "script")`
  bị trình biên dịch xếp vào API mới. Thay bằng thuộc tính `badgeFont`: tạo `Font` nền rồi
  chọn `base.italic()` khi font là kiểu viết tay, nên chỉ dùng API có từ lâu.

## 84. Sửa lỗi build IPA: tham chiếu `hex` còn sót

Sau khi đổi `Color.init?(hex:)` thành `Color.init?(cssHex:)`, phần thân hàm vẫn còn dùng tên
tham số cũ nên trình biên dịch báo `cannot find 'hex' in scope`. Đã đổi thành `cssHex` và quét
lại toàn bộ tệp: không còn tên `hex` trần nào ngoài chú thích.

## 85. Trang quản trị tài khoản: icon tên, danh sách chọn, hiệu ứng tên

- **Icon cạnh tên**: ô ảnh đại diện trong hàng tài khoản và ở đầu bảng chỉnh sửa giờ hiện
  chữ cái đầu của tên trên nền chuyển sắc, thay cho biểu tượng khiên bị lệch; chữ trong hàng
  tài khoản cũng được nâng cỡ cho dễ đọc và bỏ khai báo `min-width` cũ làm hàng bị co.
- **Danh sách chọn**: thêm `components/SelectField.tsx` thay toàn bộ `<select>` của trình duyệt
  (quyền, kiểu nhãn, font, kích thước, chuyển động, hiệu ứng tên). Bảng chọn vẽ theo tông tối của
  trang, có mũi tên xoay, dòng đang chọn in đậm kèm dấu tích, đóng khi bấm ra ngoài hoặc nhấn Esc,
  hỗ trợ phím mũi tên và Enter.
- **Hiệu ứng viền chữ**: `.cin-name--outline` trước đây lấy viền theo `currentColor` mà chữ lại đặt
  trong suốt nên tên biến mất khỏi khung xem trước; nay viền lấy từ biến `--cin-name-color`.
- **Thêm hiệu ứng**: tên người dùng có thêm Neon, Ánh kim, Băng giá, Lửa, Bóng đổ, Gạch chân,
  Thở nhẹ (tổng 13 hiệu ứng); nhãn có thêm kiểu Neon, Ánh kim, Hologram và chuyển động Nhún nhảy,
  Nghiêng nhẹ, Chớp tắt. Cả web lẫn app đều dựng được các lựa chọn mới; máy chủ đã mở rộng danh
  sách giá trị hợp lệ cho `style`, `animation`, `effect`.

## 86. Giao diện trả lời bình luận: rõ đang trả lời ai

Trước đây mọi trả lời đều bị gắn về bình luận gốc nên app không biết người dùng vừa trả lời ai:
trả lời chỉ thụt lề 14pt kèm một vạch dọc mờ, trông không khác bình luận thường, còn ô soạn chỉ có
một dòng chữ nhỏ "Đang trả lời …".

- **Dữ liệu**: `CommentsStore.send` giữ đúng `parentID` của bình luận được trả lời thay vì nhảy lên
  bình luận gốc; cây vẫn chỉ lồng một cấp vì `rebuild()` gom mọi trả lời về gốc của nhánh. Nhờ vậy
  app biết chính xác ai đang được trả lời, kể cả sau khi tải lại danh sách.
- **Xoá theo nhánh**: vì nhánh có thể sâu vài tầng, `CommentsStore.delete`, `deleteMovieComment`
  (server Node) và bản PHP `cpanel-comments` đều xoá toàn bộ trả lời nằm bên dưới, không để lại
  bình luận mồ côi.
- **Thẻ trả lời**: mỗi trả lời là một thẻ bo góc 16pt có nền sáng nhẹ, vạch tím chuyển sắc bên trái
  và khoảng đệm riêng, tách hẳn khỏi bình luận gốc.
- **Dòng ngữ cảnh**: đầu mỗi trả lời có "↩ Trả lời <tên>" (giữ nguyên nhãn và hiệu ứng tên của người
  được trả lời) kèm trích đoạn 40 ký tự của bình luận gốc.
- **Ô soạn**: thay dòng chữ nhỏ bằng thẻ "Đang trả lời" có ảnh đại diện, tên người được trả lời và
  trích đoạn nội dung, viền tím nhạt cùng nút huỷ rõ ràng.
- **Đánh dấu đích**: bình luận đang được trả lời có viền tím và nút "Trả lời" đổi màu, nên khi cuộn
  trong luồng dài vẫn thấy mình đang trả lời bình luận nào.
- **Web admin**: `groupComments` đi ngược lên gốc nhánh nên trả lời của trả lời không còn bị bỏ sót
  khỏi danh sách bình luận trong trang quản trị.

## 87. Nhãn hiển thị bằng ảnh/GIF hết khoảng trống sau tên

Khung ảnh nhãn chỉ đặt `maxWidth` nên trong hàng bình luận nó luôn chiếm 64pt trong khi ảnh chỉ vẽ
đúng bề rộng của mình — phần dư ra thành một khoảng trống lớn giữa tên người dùng và nhãn.

- `CommentBadgeImage` nay tự tính bề rộng theo tỉ lệ khung hình của khung đầu tiên
  (`imageHeight * ratio`), chặn trên 64pt, nên khung vừa khít ảnh; nhãn quá dài vẫn bị giới hạn.
- Trong lúc ảnh đang tải, khung rộng 0 nên không còn khoảng trống chờ, và bề rộng đổi bằng
  `Motion.gentle` khi ảnh hiện ra.
- Ảnh động (GIF/WebP) vẫn chạy khung hình như trước; bản web vốn đã đúng (`width: auto`).

## 88. Trang quản trị: danh sách phim thủ công gọn lại, Ngôn ngữ chọn nhiều, tải mượt hơn

- **Phim thủ công thành danh sách riêng**: cột phải nay có ô tìm nhanh và khung cuộn cao tối đa
  ~430px, nên thêm bao nhiêu phim trang cũng không dài xuống; poster tải lười (`loading="lazy"`).
- **Ngôn ngữ**: ba lựa chọn nhanh viết hoa đầu từ (Vietsub giữ nguyên, Thuyết Minh, Lồng Tiếng) và
  chọn được **nhiều mục cùng lúc**; giá trị lưu là "Thuyết Minh + Lồng Tiếng" nên app hiển thị đúng
  chuỗi này. Bản cũ lưu "Thuyết minh" vẫn khớp nhờ so khớp bỏ dấu, không phân biệt hoa thường, và
  khi lưu lại sẽ tự chuẩn hoá. Ô "Ngôn ngữ khác" vẫn dùng để ghi kiểu như "Vietsub AI".
- **Bộ lọc trong app** đổi nhãn thành "Thuyết Minh" / "Lồng Tiếng" cho khớp; phép so khớp vốn
  không phân biệt hoa thường nên phim cũ vẫn lọc đúng.
- **Hiệu năng trang Thêm phim thủ công**: danh sách phim và khối Nguồn & tập được ghi nhớ
  (`memo`), danh sách chỉ dựng lại khi dữ liệu đổi, ô tìm trong danh sách dùng `useDeferredValue`,
  nên gõ trong form không còn dựng lại toàn bộ cây giao diện.
- **Hiệu năng trang Quản lý phim & bình luận**: bình luận chỉ nhóm/sắp xếp lại khi danh sách đổi,
  mỗi dòng phim là component ghi nhớ riêng, ảnh poster và ảnh đại diện tải lười.

## 89. Năm yêu cầu: danh sách "Xem thêm", thẻ đề xuất, tải xuống, kênh trực tiếp, âm lượng máy

- **Danh sách "Xem thêm" không còn cảm giác tải lại**: `CinemaStore` giữ nội dung từng mục theo
  `kind` (`SectionListCache`), nên khi quay ra từ trang chi tiết phim, danh sách hiện lại nguyên
  trạng thái cũ thay vì trắng rồi tải lại. Thẻ phim dùng `auroraReveal(_, key:)` với khoá là id
  phim — mỗi phim chỉ chạy hiệu ứng vào **một lần** trong phiên (`AuroraRevealRegistry`), không
  trượt lại cả lưới mỗi lần quay về. Việc nạp thêm trang khi cuộn tới cuối bị chặn trong 1,5 giây
  đầu sau khi màn hiện lại, nên không tự nhiên có thêm phim mới ngay khi vừa trở ra.
- **Thẻ "Đề xuất hôm nay"** (`FeaturedMovieCard`) được làm lại: hai lớp mờ (một lớp giữ cho nhãn và
  thanh trạng thái đọc được), dòng nhãn nhỏ "thể loại · năm · chất lượng", tên phim lớn hơn kèm bóng
  đổ nhẹ, tên gốc, hai nhãn kính mờ cho ngôn ngữ và số tập, huy hiệu điểm số ở góc phải, và hai nút
  "Xem ngay" / "Chi tiết". Không thêm hiệu ứng chạy liên tục.
- **Tải xuống**: chỉ tải qua **Wi-Fi**. `DownloadManager` tự theo dõi mạng (`NWPathMonitor`): không có
  Wi-Fi thì mục nằm ở trạng thái chờ kèm lời nhắc; rời Wi-Fi giữa chừng thì tự tạm dừng để không tốn
  dữ liệu di động; Wi-Fi trở lại thì phần đang chờ tự chạy tiếp, còn mục đã tạm dừng vẫn chờ người
  dùng bấm "Tải tiếp" (và nút đó cũng cần Wi-Fi). Màn Tải xuống có băng nhắc màu vàng.
- **Tải mượt hơn**: trước đây mỗi lô 3 phân đoạn lại mã hoá JSON và ghi tệp một lần — nay ghi tối đa
  3 giây một lần (mốc trạng thái quan trọng vẫn ghi ngay), và việc kiểm tra dung lượng trống được
  giãn ra. Xem phim trong lúc tải vẫn hoạt động: tác vụ tải không bị dừng khi mở trình phát, tập nào
  chưa tải xong thì phát từ nguồn online.
- **Trình phát KÊNH TRUYỀN HÌNH**: thanh công cụ không tự ẩn khi nguồn phát chưa tải xong (chờ tối đa
  30 giây rồi mới đếm 4 giây như cũ), nhờ vậy vẫn thấy dòng "Đang tải nguồn phát…" và nút Đồng bộ.
  Thêm cơ chế tự phục hồi: nếu sau 6 giây và 11 giây nguồn vẫn ở trạng thái chờ thì hệ thống tự dựng
  lại nguồn (tối đa 2 lần cho mỗi lần mở kênh) thay vì bắt người xem bấm Đồng bộ.
- **Âm lượng theo máy**: thêm `SystemVolume` dùng `MPVolumeView` ẩn để chỉnh **âm lượng của thiết bị**
  (trước đây chỉnh âm lượng riêng của AVPlayer nên máy vẫn to). Áp dụng cho trình phát phim, trình
  phát kênh trực tiếp và trình phát video đã đăng; thanh trượt, nút tắt tiếng và thao tác vuốt dọc
  đều đi theo âm lượng máy, và khi bấm nút cứng bên hông máy thì thanh trượt trong app cập nhật theo.

## 90. Sửa lỗi thanh âm lượng hệ thống lộ ra trên giao diện

- Bản 89 đặt một neo `MPVolumeView` 2×2 trong từng trình phát. Khung nhỏ **không** cắt được
  nội dung bên trong vì `UIView` mặc định `clipsToBounds = false`, nên thanh âm lượng của hệ
  thống cùng nút loa lộ hẳn ra ngoài và dính lên thẻ phim ở trang chủ.
- Nay chỉ còn **một** `MPVolumeView` gắn trực tiếp vào cửa sổ ứng dụng từ gốc app
  (`SystemVolumeWindowInstaller`): kích thước 1×1, `clipsToBounds = true`, `alpha = 0.001`,
  không nhận chạm và đưa xuống dưới cùng. Các neo trong trình phát phim và trình phát kênh
  trực tiếp đã được bỏ.
- Sau khi gắn, bố cục được ép chạy ngay để thanh trượt con tồn tại, nên lần chỉnh âm lượng
  đầu tiên đã có tác dụng.

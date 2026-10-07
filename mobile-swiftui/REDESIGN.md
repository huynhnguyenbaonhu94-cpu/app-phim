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

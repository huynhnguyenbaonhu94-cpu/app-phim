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

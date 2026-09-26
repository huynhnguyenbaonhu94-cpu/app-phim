# Cinemora Native Mobile — Audit & Refactor Summary

## Kết quả

Project đã được chuyển thành một **native Expo/React Native app độc lập** trong `mobile/`. Codemagic chỉ build thư mục `mobile/`; `client/` và backend ở root không tham gia render UI native.

- Không dùng iframe, website redirect hoặc WebView để render app.
- Không import UI, router, CSS hay state của web app vào mobile.
- API hiện tại vẫn được giữ qua `mobile/src/api.ts` để bảo toàn data flow và contract.
- Player native `expo-video` vẫn giữ watchdog, seek recovery, fullscreen, orientation, episode/source picker, volume gesture và fit selector.

## Audit trước refactor

| Hạng mục | Kết luận |
|---|---|
| Framework | Expo SDK 54, React Native 0.81, Expo Router 6 |
| Entry point | `mobile/app/_layout.tsx` → Expo Router file-based routes |
| Mobile architecture | Native screens trong `mobile/app/`, service/API trong `mobile/src/api.ts` |
| Web architecture | React/Vite trong `client/`, backend Node/tRPC ở root; không nằm trong native build |
| Shared code | Chỉ giữ model/API helpers thuần logic; không dùng web components |
| Navigation | Expo Router Stack + bottom Tabs, native push/fullscreen modal |
| State | Local React state/hooks; player state dùng native `expo-video` listeners |
| API | tRPC HTTP query tới `https://cungcapicloud.id.vn/api/trpc` |
| Player | HLS native với `expo-video`, seek watchdog/recovery và picker |
| iOS source cũ | Root `ios/` là Capacitor project cũ, đã loại bỏ khỏi source giao hàng |
| Signing | Codemagic-managed profiles qua `xcode-project use-profiles` |

## Cấu trúc mobile sau refactor

```text
mobile/
├── app/
│   ├── _layout.tsx                 # Root Stack + orientation policy
│   ├── (tabs)/
│   │   ├── _layout.tsx             # Glass bottom tab navigation
│   │   ├── index.tsx               # Home
│   │   ├── catalog.tsx             # Catalog/filter/directory
│   │   ├── search.tsx              # Native search
│   │   └── account.tsx             # Account surface
│   └── movie/[slug].tsx            # Detail + native HLS player
├── src/
│   ├── api.ts                      # API/data layer
│   ├── design.ts                   # Central tokens
│   └── ui.tsx                      # Reusable Glass UI primitives
├── assets/
├── app.json
├── package.json
└── package-lock.json
```

## Design system / Liquid Glass

`mobile/src/design.ts` tập trung:

- Colors: background, glass, border, primary, text, error/success/warning.
- Typography: display, title, section, body, label, caption.
- Spacing, radius, shadow/blur và motion durations.
- Dark-first iOS visual language với fallback nhẹ trên nền tảng không hỗ trợ blur mạnh.

`mobile/src/ui.tsx` cung cấp các primitive dùng chung:

- `GlassContainer`, `GlassCard`
- `GlassButton`, `GlassIconButton`
- `GlassState`
- `GlassMenu`
- `MovieCard`, `Poster`, `SectionTitle`
- Shared tab-bar animation và screen styles

Các màn hình Home, Catalog, Search, Account, navigation và player tiếp tục dùng chung token/component thay vì tạo glass style rời rạc.

## Web dependency cleanup

### Đã loại bỏ khỏi native mobile

- `@react-native-async-storage/async-storage`: chưa được dùng trong source native.
- `@react-navigation/native`: Expo Router đã cung cấp navigation runtime cần thiết.
- Root Capacitor iOS project (`ios/`) và Podfile Capacitor cũ.
- Mọi khả năng phụ thuộc vào `client/`, Vite, wouter, DOM, CSS, iframe hoặc website để render native UI.

### Vẫn giữ lại và lý do

- `expo-router`: native routing và deep-link entry point.
- `expo-video`: HLS player native.
- `expo-blur`: Liquid Glass và translucent tab bar.
- `expo-image`: cache/image loading hiệu quả.
- `expo-screen-orientation`: portrait policy và fullscreen landscape handling.
- `expo-font`, `expo-linking`: peer dependencies bắt buộc cho Expo Router/vector icons production.
- `react-native-safe-area-context`, `react-native-screens`: notch/Dynamic Island và native navigation.

Web `client/` và backend root vẫn được giữ trong repository để không phá website/backend hiện hữu, nhưng Codemagic native workflow không build hoặc import chúng.

## Player functionality được giữ

- Native HLS playback qua `expo-video`.
- Loading watchdog 12 giây và error state có retry.
- Seek bar drag, ±10 giây, native `seekBy` và recovery khi HLS stall.
- Controls tự ẩn, tap để hiện/ẩn, lock controls.
- Fullscreen native với orientation handling và safe-area aware layout.
- Episode picker và server/source picker trong fullscreen.
- Volume slider, mute/double-tap behavior, volume swipe gesture.
- Video fit selector `contain` / `fill` / `cover`.

## Codemagic / iOS

Workflow `cinemora-ios` hiện:

1. `cd mobile && npm ci --legacy-peer-deps`.
2. Xóa `mobile/ios` cũ và chạy Expo prebuild sạch.
3. Chạy `pod install --repo-update` trong `mobile/ios`.
4. Chạy `xcode-project use-profiles` từ root repository.
5. Build `mobile/ios/Cinemora.xcworkspace`, scheme `Cinemora`, Release.
6. Thu artifact tại `mobile/build/ios/ipa/*.ipa`.

Bundle ID: `app.serval4238.taurus3258`.
API base URL mặc định: `https://cungcapicloud.id.vn`.
Không có certificate, password, JWT secret hoặc database secret trong source.

## Verification đã chạy

- `npm ci --legacy-peer-deps` — thành công.
- `npm run typecheck` — thành công.
- `npx expo-doctor@latest` — **18/18 checks passed**.
- `npx expo export --platform ios` — bundle iOS thành công.
- Codemagic YAML đã được rà soát lại về working directory và artifact path.

## Known issues / giới hạn môi trường

1. **Không thể build IPA trực tiếp trong Linux sandbox**: Xcode, CocoaPods runtime và Apple signing chỉ có trên macOS/Codemagic. Workflow đã chuẩn bị để Codemagic thực hiện bước này.
2. **Ad Hoc signing cần cấu hình Codemagic/Apple Developer**: profile phải khớp bundle ID và UDID thiết bị. Nếu phát hành TestFlight/App Store, đổi `distribution_type` và profile tương ứng.
3. **NPM audit còn cảnh báo transitive dependencies**: Expo dependency tree hiện báo 16 vulnerabilities sau install; không dùng `npm audit fix --force` vì có thể phá bộ version Expo SDK. Cần review riêng trên CI trước khi release.
4. **API/backend vẫn cần online**: app native không phụ thuộc Web UI, nhưng các catalog/detail/stream data vẫn lấy từ API hiện có theo yêu cầu giữ functionality.

## Lệnh build

```bash
cd mobile
npm ci --legacy-peer-deps
npm run typecheck
npx expo-doctor
npx expo prebuild --platform ios --clean --non-interactive
```

Trên Codemagic, chỉ cần commit toàn bộ repository và chọn workflow `cinemora-ios`.

## Patch v3 — earlier interface update

- Home screen was redesigned as a full-bleed cinematic hero with backdrop image, dark wash, glass border, overlay metadata and a watch CTA.
- The source archive supplied for the current pass still contained a second `Modal` for the fullscreen picker despite this earlier audit note. Patch v4 below removes it and keeps the picker in the existing fullscreen presentation.

## Patch v4 — Liquid Glass và ổn định chuyển tập

- Mở rộng Liquid Glass thành design system dùng chung: ambient screen light, blur/overlay, specular edge, typography/radius/màu sắc và các card/menu trạng thái thống nhất cho toàn bộ các màn native.
- Loại bỏ native `Modal` lồng trong modal fullscreen. Danh sách tập/nguồn là overlay có thể chạm/đóng trong cùng một fullscreen presentation, duy trì orientation và player.
- Không gọi `player.replace()` ngay sau khi `useVideoPlayer` đã khởi tạo nguồn mới theo URI. Mỗi player mới có watchdog 18 giây, dọn subscriptions/timer khi unmount; thao tác thử lại gọi `replaceAsync` và chuyển sang lỗi/retry nếu nguồn không sẵn sàng.
- Đồng bộ màu splash với nền theme mới.
- Xác minh lại trên source: `npm run typecheck` thành công; `npx expo export --platform ios` tạo bundle iOS thành công; `npx expo-doctor` báo 18/18 checks passed. Kiểm thử thao tác trên thiết bị và tạo IPA vẫn cần Codemagic/iPhone thật.

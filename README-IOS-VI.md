# Cinemora Native iOS — build IPA bằng Codemagic

Source đã được chuyển từ mô hình **Capacitor bọc React/Vite WebView** sang **React Native/Expo native**. App nằm trong thư mục `mobile/`, còn backend Node/tRPC hiện có ở thư mục gốc vẫn được giữ lại. Giao diện iPhone không còn chạy từ `dist/public` và không còn phụ thuộc vào Capacitor.


> Lưu ý: Source này ưu tiên build ứng dụng iOS bằng **Codemagic trên website**. Không cần và không nên build `.ipa` trực tiếp trong sandbox/local; chỉ commit toàn bộ repository lên GitHub rồi chạy workflow `cinemora-ios` trong Codemagic.

## Cấu trúc mới

- `mobile/app/`: màn hình native với Expo Router: Trang chủ, Thư viện, Tìm kiếm, Tài khoản và Chi tiết phim.
- `mobile/src/api.ts`: lớp gọi API tRPC bằng `fetch`, không dùng `window`, DOM hoặc Vite runtime.
- `mobile/src/ui.tsx`: theme và component native dùng chung.
- `mobile/app/movie/[slug].tsx`: trình phát HLS native bằng `expo-video`.
- `codemagic.yaml`: cài dependency, chạy Expo prebuild, CocoaPods và build IPA có signing.
- `server/`, `client/`: backend và bản web cũ được giữ để website hiện tại không bị mất; Codemagic native không build thư mục `client`.

## Cấu hình API

App native mặc định gọi `https://cungcapicloud.id.vn/api/trpc`. Nếu đổi domain, sửa `mobile/app.json` tại `expo.extra.apiBaseUrl`. Không đưa `DATABASE_URL`, `JWT_SECRET` hoặc secret backend vào source mobile.

## Build local

```sh
cd mobile
npm install --legacy-peer-deps
npx expo start
```

Để tạo project iOS native trên macOS:

```sh
cd mobile
npx expo prebuild --platform ios
cd ios && pod install
```

## Build IPA trên Codemagic

1. Đưa toàn bộ repository lên GitHub, bao gồm thư mục `mobile/` và file `codemagic.yaml`.
2. Trong Codemagic chọn workflow **Cinemora Native iOS IPA**.
3. Kết nối Apple Developer và cấu hình signing/provisioning cho Bundle ID `app.serval4238.taurus3258`.
4. Chạy build. Codemagic sẽ tự sinh `mobile/ios`, chạy CocoaPods và xuất `.ipa` ở Artifacts.

Workflow hiện dùng signing của Codemagic (`xcode-project use-profiles`), không còn tắt code signing như bản Capacitor cũ. Vì vậy cần provisioning profile hợp lệ. Nếu muốn TestFlight/App Store, dùng distribution certificate và App Store provisioning profile; nếu cài trực tiếp lên thiết bị, dùng Ad Hoc profile có UDID.

## Lưu ý backend

Backend phải cho phép request từ app native và vẫn phục vụ route `https://cungcapicloud.id.vn/api/trpc`. Phần phim, danh mục, tìm kiếm, chi tiết, episode và link stream được native app gọi trực tiếp từ các procedure `cinema.*`. Đăng nhập, yêu thích và lịch sử là phần backend đã có; màn hình tài khoản native đang để sẵn điểm tích hợp, có thể nối tiếp mà không cần đổi API.

## Bản chỉnh giao diện và player

- Giao diện native được đồng bộ theo Liquid Glass: nền tối có ánh sáng môi trường, bề mặt blur trong suốt, viền sáng mảnh, card poster và các trạng thái/menu đồng nhất trên Trang chủ, Thư viện, Tìm kiếm, Tài khoản và Chi tiết phim.
- Picker tập/nguồn trong fullscreen được render đè ngay trong presentation fullscreen hiện tại, không mở một `Modal` native lồng bên trong — tránh lỗi thoát app trên iOS.
- Khi chuyển tập, `useVideoPlayer` tạo player mới theo URI mới; code không gọi thay source lần thứ hai trên player vừa tạo. Watchdog hiển thị trạng thái lỗi có thể thử lại thay vì để loading vô hạn; retry dùng `replaceAsync`.
- Đã kiểm tra: `npm run typecheck`, `npx expo export --platform ios`, `npx expo-doctor` (18/18). IPA vẫn được ký và build trên Codemagic; môi trường Linux này không có Xcode/signing để tạo IPA trực tiếp.

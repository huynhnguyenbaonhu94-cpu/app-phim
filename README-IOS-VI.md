# Cinemora Native iOS — build IPA bằng Codemagic

Source đã được chuyển từ mô hình **Capacitor bọc React/Vite WebView** sang **React Native/Expo native**. App nằm trong thư mục `mobile/`, còn backend Node/tRPC hiện có ở thư mục gốc vẫn được giữ lại. Giao diện iPhone không còn chạy từ `dist/public` và không còn phụ thuộc vào Capacitor.


> Bản hiện tại đặt **SwiftUI native** làm app mặc định cho Codemagic. Không cần build `.ipa` trong sandbox/local; commit toàn bộ repository lên GitHub rồi chạy workflow `cinemora-ios`.

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

1. Đưa toàn bộ repository lên GitHub, bao gồm thư mục `mobile-swiftui/`, `mobile/` và file `codemagic.yaml`.
2. Trong Codemagic chọn workflow **Cinemora Native iOS IPA (SwiftUI)** (`cinemora-ios`). Đây là workflow mặc định; Codemagic cài XcodeGen, tạo project Xcode từ SwiftUI source, kiểm tra scheme rồi build IPA.
3. Kết nối Apple Developer và cấu hình signing/provisioning cho Bundle ID `app.serval4238.taurus3258`.
4. Chạy build. IPA xuất hiện trong Artifacts khi build thành công.

Workflow hiện dùng signing của Codemagic (`xcode-project use-profiles`), không còn tắt code signing như bản Capacitor cũ. Vì vậy cần provisioning profile hợp lệ. Nếu muốn TestFlight/App Store, dùng distribution certificate và App Store provisioning profile; nếu cài trực tiếp lên thiết bị, dùng Ad Hoc profile có UDID.

## Thử nghiệm app SwiftUI native riêng

Ứng dụng SwiftUI nằm riêng trong `mobile-swiftui/`. App Expo trong `mobile/` vẫn được giữ làm phương án quay lại nếu bản SwiftUI chưa đạt.

1. Push source cập nhật lên GitHub như các lần trước.
2. Trong Codemagic, chọn workflow **Cinemora Native iOS IPA (SwiftUI)** (`cinemora-ios`). Workflow này cài XcodeGen, tạo `Cinemora.xcodeproj`, ký rồi build IPA.
3. Kiểm tra IPA trên iPhone thật, đặc biệt đăng nhập API, ảnh, phát HLS và nguồn embed.
4. Nếu bản SwiftUI build lỗi hoặc chưa đạt, chọn workflow **Cinemora Expo iOS IPA (fallback)** (`cinemora-expo-ios`); app Expo cũ vẫn còn nguyên.

App SwiftUI có giao diện native; dùng Liquid Glass hệ thống trên iOS 26 và material fallback trên iOS 17–25. Source đã rà cú pháp và API trong môi trường Linux nhưng chưa compile bằng Xcode, chạy Simulator hay ký IPA; cần kiểm tra log và thử IPA Codemagic trước khi phát hành.

## Lưu ý backend

Backend phải cho phép request từ app native và vẫn phục vụ route `https://cungcapicloud.id.vn/api/trpc`. Phần phim, danh mục, tìm kiếm, chi tiết, episode và link stream được native app gọi trực tiếp từ các procedure `cinema.*`. Đăng nhập, yêu thích và lịch sử là phần backend đã có; màn hình tài khoản native đang để sẵn điểm tích hợp, có thể nối tiếp mà không cần đổi API.

## Bản chỉnh giao diện và player

- Giao diện native được đồng bộ theo Liquid Glass: nền tối có ánh sáng môi trường, bề mặt blur trong suốt, viền sáng mảnh, card poster và các trạng thái/menu đồng nhất trên Trang chủ, Thư viện, Tìm kiếm, Tài khoản và Chi tiết phim.
- Picker tập/nguồn trong fullscreen được render đè ngay trong presentation fullscreen hiện tại, không mở một `Modal` native lồng bên trong — tránh lỗi thoát app trên iOS.
- Khi chuyển tập, `useVideoPlayer` tạo player mới theo URI mới; code không gọi thay source lần thứ hai trên player vừa tạo. Watchdog hiển thị trạng thái lỗi có thể thử lại thay vì để loading vô hạn; retry dùng `replaceAsync`.
- Đã kiểm tra: `npm run typecheck`, `npx expo export --platform ios`, `npx expo-doctor` (18/18). IPA vẫn được ký và build trên Codemagic; môi trường Linux này không có Xcode/signing để tạo IPA trực tiếp.

## Patch v5 — picker dễ đọc, không tự đóng

- Thay carousel cuộn ngang khó đọc bằng sheet tương phản cao, bố cục lưới tự xuống dòng, hiện rõ tập/nguồn đang chọn và có scroll dọc khi danh sách dài.
- Picker state được đưa lên `Player` và sheet render độc lập với toolbar; chuyển tập làm toolbar tạm unmount/hiện loading không còn làm đóng picker.
- Chọn tập/nguồn cập nhật playback và lựa chọn hiện tại nhưng sheet tiếp tục mở; chỉ nút đóng hoặc chạm backdrop mới đóng.

## Patch v6 — fullscreen title và mute một chạm

- Nhãn phim trong fullscreen nằm trong hàng điều khiển, dùng phần không gian co giãn ở giữa title và các nút; tên dài tự cắt bằng dấu ba chấm thay vì phủ icon.
- Icon loa giờ đổi trạng thái tiếng ngay ở lần chạm đầu tiên. Bật tiếng phục hồi mức âm lượng gần nhất; kéo thanh về 0 rồi chạm icon cũng khôi phục mức đó. Thanh chỉnh âm lượng vẫn mở tạm thời khi chạm icon.

## Patch v7 — volume controls và error fullscreen

- Chạm icon loa ngoài chỉ mở/ẩn thanh chỉnh âm lượng; không còn đổi mute ngoài ý muốn. Thanh kéo có nút mute/unmute riêng với hit-target lớn, giữ chế độ một chạm và khôi phục âm lượng gần nhất.
- Trạng thái lỗi trong fullscreen có nút `Trở lại` ở góc trên trái để thoát fullscreen về player ở màn chi tiết.

## Patch v8 — thanh điều hướng Liquid Glass

- Thay tab bar mặc định bằng custom tab bar kính mờ có lớp specular, viền sáng, capsule active và chấm chỉ báo hoạt động.
- Chuyển động đổi tab dùng spring native-driver cho icon/capsule; khi cuộn nội dung xuống, thanh trượt khỏi cạnh dưới và mờ nhẹ; vuốt lên hoặc về đầu trang thì trượt lại.
- Không thêm package animation mới; dùng `Animated` của React Native cùng Expo Blur.

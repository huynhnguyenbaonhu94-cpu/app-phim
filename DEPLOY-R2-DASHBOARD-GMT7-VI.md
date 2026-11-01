# Cập nhật lịch R2 GMT+7 và Dashboard quản trị

## Lịch backup theo giờ Việt Nam

Bản cập nhật dùng múi giờ cố định `Asia/Ho_Chi_Minh` (GMT+7) cho lịch backup hàng ngày/hàng tuần. Trang cài đặt hiển thị giờ Việt Nam; scheduler không còn phụ thuộc vào timezone cấu hình trên máy chủ cPanel.

Khi ứng dụng khởi động, `ensureR2Compatibility` tự thêm cột `scheduleHourVietnam` nếu database cũ chưa có. Giá trị UTC cũ được chuyển sang giờ Việt Nam bằng cách cộng 7 giờ theo vòng 24 giờ, để giữ nguyên thời điểm chạy tương đương. Cột `scheduleHourUtc` cũ được giữ lại và đồng bộ để tương thích với trường hợp cần rollback mã nguồn.

Thông thường chỉ cần cập nhật source, build và restart ứng dụng Node.js; startup guard tự chuyển đổi một lần. File `drizzle/0012_r2_vietnam_schedule_timezone.sql` chỉ dành cho trường hợp quản trị viên muốn chạy chuyển đổi SQL thủ công trước khi bật source mới. **Không chạy lại SQL nếu cột `scheduleHourVietnam` đã tồn tại.** Sao lưu database trước khi nâng cấp.

Lịch vẫn chỉ thực thi khi tiến trình Node.js đang chạy và R2 đã cấu hình hợp lệ. Scheduler kiểm tra theo chu kỳ khoảng một phút.

## Tự lưu poster và thumbnail phim nguồn API

Khi app iOS hoặc web tải poster/thumbnail của catalog API, backend tự lưu bản ảnh raster hợp lệ vào `public-assets/movie-artwork/` trên R2 bằng khóa theo nội dung. Ảnh đã lưu được phục vụ qua route public-storage; URL proxy cũ cũng sẽ chuyển sang bản R2 khi ảnh đã được mirror. Vì vậy các poster đã mở không còn phụ thuộc việc máy chủ ảnh gốc tiếp tục hoạt động. Mirror chạy nền, giới hạn kích thước và chỉ theo HTTPS từ các host ảnh đã cho phép; không áp dụng lên link video/HLS.

Tính năng dùng chung cấu hình R2 hiện có trong trang quản trị và không cần thêm migration database. Nếu R2 chưa cấu hình/không truy cập được hoặc nguồn trả về dữ liệu không phải ảnh raster hợp lệ, backend giữ fallback proxy hiện tại thay vì trả URL R2 giả. Bản cũ đã lưu vẫn được dùng nếu lần refresh nguồn thất bại.

## Backfill catalog hiện có

Ngoài mirror tự động khi người dùng xem phim, trang `/admin/r2-settings` có card **Sao lưu artwork catalog lên R2**. Sau khi cấu hình và kiểm tra R2, admin có thể bắt đầu một lượt quét catalog hiện có. Worker duyệt danh sách cập nhật và các danh mục phim lẻ, phim bộ, TV shows, hoạt hình, Vietsub, thuyết minh, lồng tiếng, subteam và phim chiếu rạp; các URL ảnh trùng nhau được khử trùng lặp trước khi mirror. Phạm vi là poster/thumbnail của catalog API, không phải video/HLS.

Card hiển thị số trang, số ảnh đã phát hiện, số ảnh lưu thành công và ảnh cần thử lại; admin có thể tạm dừng, tiếp tục, hoặc chạy lại các ảnh lỗi. Checkpoint và hàng đợi ảnh được lưu trong MySQL. Bảng trạng thái được tự tạo bởi compatibility guard khi backend khởi động; không cần chạy SQL thủ công. Nếu tiến trình Node.js bị restart giữa chừng, worker sẽ nhận lại lượt đang chạy khi lease hết hạn và tiếp tục từ trang/ảnh chưa hoàn tất. Thao tác **Quét lại catalog** tạo một lượt mới và thay thế hàng đợi/lịch sử lỗi hiện tại; không xóa object artwork đã có trên R2.

Backfill chỉ bắt đầu khi admin bấm nút, không tự chạy ngay sau khi deploy. Nó kiểm tra kết nối R2 trước khi khởi chạy, xử lý tối đa hai ảnh đồng thời và dùng lại `mirrorMovieArtwork`/manifest content-addressed hiện có. Ảnh lỗi không làm cả lượt quét dừng; backend ghi lại để admin thử lại sau. Nếu R2 hoặc một trang catalog bị lỗi liên tục, tác vụ tạm dừng ở checkpoint thay vì tiếp tục báo thành công giả.

## Dashboard

Đăng nhập tài khoản có role `admin`, sau đó mở `/admin` hoặc chọn **Quản trị/Dashboard quản trị** trên menu đầu trang. API `adminDashboard.overview` được bảo vệ bằng `adminProcedure`. Chỉ số tổng hợp đọc từ các bảng hiện có; mục phim hiển thị rõ là phim thủ công để không nhầm với catalog từ nguồn API bên ngoài.

## Cập nhật cPanel

1. Sao lưu database và lưu lại cấu hình môi trường hiện tại.
2. Giải nén source backend mới lên thư mục ứng dụng.
3. Cài dependency nếu cần, chạy `pnpm run check`, `pnpm test` và `pnpm run build` (hoặc lệnh npm đang dùng trên hosting).
4. Restart ứng dụng Node.js để chạy schema compatibility guard.
5. Mở `/admin/r2-settings`, xác nhận lịch hiển thị giờ GMT+7 và lưu lại nếu cần. Kiểm tra kết nối R2 trước khi bật lịch.
6. Mở `/admin` để xem Dashboard. Nếu trình duyệt còn dùng bundle cũ, hard refresh hoặc xóa cache trang.

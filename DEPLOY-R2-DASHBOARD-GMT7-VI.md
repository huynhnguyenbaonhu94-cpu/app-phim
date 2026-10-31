# Cập nhật lịch R2 GMT+7 và Dashboard quản trị

## Lịch backup theo giờ Việt Nam

Bản cập nhật dùng múi giờ cố định `Asia/Ho_Chi_Minh` (GMT+7) cho lịch backup hàng ngày/hàng tuần. Trang cài đặt hiển thị giờ Việt Nam; scheduler không còn phụ thuộc vào timezone cấu hình trên máy chủ cPanel.

Khi ứng dụng khởi động, `ensureR2Compatibility` tự thêm cột `scheduleHourVietnam` nếu database cũ chưa có. Giá trị UTC cũ được chuyển sang giờ Việt Nam bằng cách cộng 7 giờ theo vòng 24 giờ, để giữ nguyên thời điểm chạy tương đương. Cột `scheduleHourUtc` cũ được giữ lại và đồng bộ để tương thích với trường hợp cần rollback mã nguồn.

Thông thường chỉ cần cập nhật source, build và restart ứng dụng Node.js; startup guard tự chuyển đổi một lần. File `drizzle/0012_r2_vietnam_schedule_timezone.sql` chỉ dành cho trường hợp quản trị viên muốn chạy chuyển đổi SQL thủ công trước khi bật source mới. **Không chạy lại SQL nếu cột `scheduleHourVietnam` đã tồn tại.** Sao lưu database trước khi nâng cấp.

Lịch vẫn chỉ thực thi khi tiến trình Node.js đang chạy và R2 đã cấu hình hợp lệ. Scheduler kiểm tra theo chu kỳ khoảng một phút.

## Dashboard

Đăng nhập tài khoản có role `admin`, sau đó mở `/admin` hoặc chọn **Quản trị/Dashboard quản trị** trên menu đầu trang. API `adminDashboard.overview` được bảo vệ bằng `adminProcedure`. Chỉ số tổng hợp đọc từ các bảng hiện có; mục phim hiển thị rõ là phim thủ công để không nhầm với catalog từ nguồn API bên ngoài.

## Cập nhật cPanel

1. Sao lưu database và lưu lại cấu hình môi trường hiện tại.
2. Giải nén source backend mới lên thư mục ứng dụng.
3. Cài dependency nếu cần, chạy `pnpm run check`, `pnpm test` và `pnpm run build` (hoặc lệnh npm đang dùng trên hosting).
4. Restart ứng dụng Node.js để chạy schema compatibility guard.
5. Mở `/admin/r2-settings`, xác nhận lịch hiển thị giờ GMT+7 và lưu lại nếu cần. Kiểm tra kết nối R2 trước khi bật lịch.
6. Mở `/admin` để xem Dashboard. Nếu trình duyệt còn dùng bundle cũ, hard refresh hoặc xóa cache trang.

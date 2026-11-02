# Cập nhật lịch R2 GMT+7 và Dashboard quản trị

## Lịch backup theo giờ Việt Nam

Bản cập nhật dùng múi giờ cố định `Asia/Ho_Chi_Minh` (GMT+7) cho lịch backup hàng ngày/hàng tuần. Trang cài đặt hiển thị giờ Việt Nam; scheduler không còn phụ thuộc vào timezone cấu hình trên máy chủ cPanel.

Khi ứng dụng khởi động, `ensureR2Compatibility` tự thêm cột `scheduleHourVietnam` nếu database cũ chưa có. Giá trị UTC cũ được chuyển sang giờ Việt Nam bằng cách cộng 7 giờ theo vòng 24 giờ, để giữ nguyên thời điểm chạy tương đương. Cột `scheduleHourUtc` cũ được giữ lại và đồng bộ để tương thích với trường hợp cần rollback mã nguồn.

Thông thường chỉ cần cập nhật source, build và restart ứng dụng Node.js; startup guard tự chuyển đổi một lần. File `drizzle/0012_r2_vietnam_schedule_timezone.sql` chỉ dành cho trường hợp quản trị viên muốn chạy chuyển đổi SQL thủ công trước khi bật source mới. **Không chạy lại SQL nếu cột `scheduleHourVietnam` đã tồn tại.** Sao lưu database trước khi nâng cấp.

Lịch vẫn chỉ thực thi khi tiến trình Node.js đang chạy và R2 đã cấu hình hợp lệ. Scheduler kiểm tra theo chu kỳ khoảng một phút.

Scheduler bỏ qua lượt tự động nếu đã có backup **thành công** trong cùng ngày (daily) hoặc cùng tuần GMT+7 (weekly), bất kể backup đó được admin chạy thủ công hay do lịch chạy. Vì vậy backup thủ công hoàn tất trước giờ hẹn sẽ ngăn tạo thêm một bản trùng trong cùng khung thời gian. Nếu backup thủ công thất bại nhưng đã có một backup thành công khác trong ngày/tuần đó, lịch vẫn xem khung đã được backup.

## Tự lưu poster và thumbnail phim nguồn API

Khi app iOS hoặc web tải poster/thumbnail của catalog API, backend tự lưu bản ảnh raster hợp lệ vào `public-assets/movie-artwork/` trên R2 bằng khóa theo nội dung. Ảnh đã lưu được phục vụ qua route public-storage; URL proxy cũ cũng sẽ chuyển sang bản R2 khi ảnh đã được mirror. Với ảnh chưa có trên R2, backend tải và trả ảnh cho người xem trước, sau đó dùng chính bộ bytes đó để ghi R2 nền; người xem không phải chờ thao tác ghi R2. Tải nguồn có tối đa ba lần thử, mỗi lần timeout 10 giây; lỗi HTTP 404 không bị thử lặp. Kiểu ảnh được nhận diện bằng chữ ký bytes thay vì chỉ tin header Content-Type. Mirror có giới hạn kích thước và chỉ theo HTTPS từ các host ảnh đã cho phép; không áp dụng lên link video/HLS.

Tính năng dùng chung cấu hình R2 hiện có trong trang quản trị, không cần chạy migration SQL thủ công. Compatibility guard tự bổ sung schema cần thiết khi backend khởi động. Nếu R2 chưa cấu hình/không truy cập được hoặc nguồn trả về dữ liệu không phải ảnh raster hợp lệ, backend giữ fallback proxy hiện tại thay vì trả URL R2 giả. Bản cũ đã lưu vẫn được dùng nếu lần refresh nguồn thất bại.

## Backfill catalog hiện có

Ngoài mirror tự động khi người dùng xem phim, trang `/admin/r2-settings` có card **Sao lưu artwork catalog lên R2**. Sau khi cấu hình và kiểm tra R2, admin có thể bắt đầu một lượt quét catalog hiện có. Worker duyệt danh sách cập nhật và các danh mục phim lẻ, phim bộ, TV shows, hoạt hình, Vietsub, thuyết minh, lồng tiếng, subteam và phim chiếu rạp; các URL ảnh trùng nhau được khử trùng lặp trước khi mirror. Phạm vi là poster/thumbnail của catalog API, không phải video/HLS.

Card chỉ hiển thị tiến độ tổng hợp: số trang, số ảnh đã phát hiện, số ảnh lưu thành công và số ảnh cần thử lại; không hiển thị danh sách từng artwork. Checkpoint và hàng đợi ảnh được lưu trong MySQL; compatibility guard tự nâng schema, không cần chạy SQL thủ công. Nếu tiến trình Node.js bị restart giữa chừng, worker sẽ nhận lại lượt đang chạy khi lease hết hạn và tiếp tục từ trang/ảnh chưa hoàn tất. Sau khi quét hết catalog, hệ thống tự thử lại mỗi ảnh lỗi thêm **một lần**; lỗi còn lại được giữ trong hàng đợi và admin có thể đưa vào lượt thử lại bằng nút trên card. Thao tác **Quét lại catalog** tạo một lượt mới và thay thế hàng đợi/lịch sử lỗi hiện tại; không xóa object artwork đã có trên R2.

Backfill chỉ bắt đầu khi admin bấm nút, không tự chạy ngay sau khi deploy. Khi bấm **Bắt đầu backfill** hoặc **Tiếp tục**, backend chỉ xác nhận kết nối R2 cần thiết rồi khởi chạy worker ngay; không đo CPU/RAM hay hiển thị bước đánh giá hosting. Worker xử lý tối đa bốn ảnh đồng thời, có giới hạn mirror dùng chung và khoảng nghỉ ngắn giữa các trang catalog; admin có thể tạm dừng nếu muốn giảm tải. Mỗi ảnh dùng tối đa ba lần gọi nguồn có timeout riêng 10 giây; lỗi 404 được ghi nhận, không tốn thêm lượt mạng tự động. Nếu R2 hoặc một trang catalog bị lỗi liên tục, tác vụ tạm dừng tại checkpoint thay vì tiếp tục báo thành công giả.

## Thống kê R2 Object Storage

Mục analytics là tùy chọn, không dùng chung S3 Access Key/Secret Key. Tạo Cloudflare API token riêng với quyền **Account → Account Analytics → Read**, nhập tại trang R2 settings và lưu; token chỉ được giữ mã hóa phía server bằng `R2_SETTINGS_ENCRYPTION_KEY`, API không trả secret về trình duyệt. Account ID được lấy từ endpoint S3 R2 đã cấu hình. Mặc định khoảng thời gian là từ đầu tháng đến hiện tại để tiện đối chiếu số liệu Overview của bucket; có thể chọn 7 hoặc 30 ngày gần nhất. Dung lượng hiển thị theo GB thập phân (1 GB = 1.000.000.000 byte), giống cách ghi dung lượng trong Cloudflare.

Cloudflare GraphQL Analytics cho R2 cho phép truy vấn tối đa 31 ngày. Class A/B được truy vấn riêng cho từng ngày và gộp theo loại thao tác/trạng thái, tránh lấy chuỗi timestamp dày rồi cộng tổng từ một tập kết quả đã chạm giới hạn 10.000 nhóm. Khi mở trang sau khi cấu hình hoặc bấm **Làm mới số liệu**, giao diện gửi truy vấn mới không dùng cache ứng dụng; trang hiển thị riêng thời điểm lấy dữ liệu và timestamp của mẫu Cloudflare mới nhất cho storage, operations, bandwidth. Bấm làm mới có thể vẫn thấy cùng số liệu nếu Cloudflare chưa có mẫu mới. Nếu một ngày vẫn chạm giới hạn kết quả, Class A/B được đánh dấu là số tối thiểu (≥), không hiển thị như tổng đầy đủ. Hạn mức mặc định của GraphQL là 300 request mỗi 5 phút cho mỗi user. Analytics có thể trễ và Class A/B không thay thế số liệu tính phí tại Billing; dataset bandwidth bỏ qua transfer nhỏ hơn 100 KiB. Nếu Cloudflare token thiếu quyền, sai Account ID/bucket hoặc analytics chưa có dữ liệu, UI báo lỗi/thông báo trống thay vì giả lập thành công.

Token được tạo theo hướng dẫn Cloudflare: [GraphQL Analytics API token authentication](https://developers.cloudflare.com/analytics/graphql-api/getting-started/authentication/api-token-auth/). Dataset, trường dữ liệu và cửa sổ 31 ngày: [R2 metrics and analytics](https://developers.cloudflare.com/r2/platform/metrics-analytics/). Danh sách Class A/B/free: [R2 pricing](https://developers.cloudflare.com/r2/pricing/). Hạn mức GraphQL: [GraphQL Analytics API limits](https://developers.cloudflare.com/analytics/graphql-api/limits/).

## Dashboard

Đăng nhập tài khoản có role `admin`, sau đó mở `/admin` hoặc chọn **Quản trị/Dashboard quản trị** trên menu đầu trang. API `adminDashboard.overview` được bảo vệ bằng `adminProcedure`. Chỉ số tổng hợp đọc từ các bảng hiện có; mục phim hiển thị rõ là phim thủ công để không nhầm với catalog từ nguồn API bên ngoài.

## Cập nhật cPanel

1. Sao lưu database và lưu lại cấu hình môi trường hiện tại.
2. Giải nén source backend mới lên thư mục ứng dụng.
3. Cài dependency nếu cần, chạy `pnpm run check`, `pnpm test` và `pnpm run build` (hoặc lệnh npm đang dùng trên hosting).
4. Restart ứng dụng Node.js để chạy schema compatibility guard.
5. Mở `/admin/r2-settings`, xác nhận lịch hiển thị giờ GMT+7 và lưu lại nếu cần. Kiểm tra kết nối R2 trước khi bật lịch.
6. Mở `/admin` để xem Dashboard. Nếu trình duyệt còn dùng bundle cũ, hard refresh hoặc xóa cache trang.

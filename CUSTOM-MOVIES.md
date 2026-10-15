# Thêm phim thủ công bằng link (website admin + app)

Tính năng cho phép admin tạo **phim mới hoàn toàn** trên website bằng link M3U8, không phụ thuộc
API nguồn. Phim tạo ra hiện trong app như phim bình thường: trang chủ, Thư viện, Tìm kiếm,
trang chi tiết (kèm diễn viên có ảnh), và phát được ngay.

## 1. Đường dẫn trên website admin
| Việc | Đường dẫn |
|---|---|
| Danh sách phim + nút **“+ Thêm phim thủ công”** | `/admin/movies` |
| Tạo phim mới | `/admin/movies/custom/new` |
| Sửa phim, thêm nguồn/tập/chất lượng | `/admin/movies/custom/<id>` |
| Nguồn & tập của một phim | `/admin/movies/sources?slug=<slug>` |

## 2. Các trường khi thêm phim
- **Tên phim**, **Tên tiếng Anh** (hiện ngay dưới tên chính trong trang chi tiết app),
  **Tên khác** (gõ xong ấn Enter để thêm tiếp, hiện ở mục “Tên khác” trong app).
- **Loại phim**: phim bộ hoặc phim lẻ; **Tập hiện tại** (ví dụ `Tập 5`, `Full`) và tổng số tập.
- **Ngày tạo**, **Thời gian cập nhật**.
- **TMDB**, **IMDB**.
- **Thể loại** và **Quốc gia**: chọn nhiều một lượt, danh sách lấy từ API nguồn (`cinema.meta`).
- **Đánh giá** (ví dụ `8.0` trên thang 10).
- **Lượt xem**: `real` = chỉ đếm lượt xem thật (tự tăng khi có người mở phim),
  `mixed` = lượt xem thật **cộng** số ảo admin nhập.
- **Poster** và **Thumbnail**: tải ảnh lên hoặc dán link, kèm trình **chỉnh sửa (cắt/zoom)** trước khi lưu.
- **Nội dung phim**.
- **Diễn viên**: thêm nhiều người, mỗi người có tên, vai, và ảnh (tải lên hoặc dán link, cắt được ảnh).
- **Nguồn & tập**: mỗi nguồn có nhiều tập; **mỗi tập có nhiều chất lượng** (1080p, 2K, 4K…),
  mỗi chất lượng có link M3U8 và **phụ đề riêng**.

## 3. Cách app đọc dữ liệu
Máy chủ trả phim thủ công **cùng hình dạng** với phim từ API nên app không cần xử lý riêng:

| Trường | Ý nghĩa trong app |
|---|---|
| `name` / `originName` | tên chính và tên tiếng Anh dưới tiêu đề |
| `alternativeNames` | mục “Tên khác” trong trang chi tiết |
| `categories` / `countries` | Thể loại / Quốc gia |
| `rating` / `views` | Đánh giá / Lượt xem |
| `actors` + `actorProfiles` | danh sách diễn viên, `actorProfiles` có ảnh |
| `createdAt` / `updatedAt` | Ngày tạo / cập nhật |
| `tmdbId` / `imdbId` | mã TMDB / IMDB |
| `servers[].episodes[].qualities` | **chọn chất lượng trong trình phát** (tab Hiển thị → Chất lượng) |

Khi tập có nhiều chất lượng, app hiện dãy nút chất lượng; đổi chất lượng sẽ nạp lại **đúng vị trí
đang xem** với link M3U8 và phụ đề của chất lượng đó.

## 4. Dữ liệu lưu ở đâu
- Bảng `custom_movies`: thông tin phim (tên, ảnh, diễn viên, thể loại, lượt xem…).
- Bảng `movie_sources` + `movie_source_episodes`: nguồn, tập, và cột `qualities` (JSON) chứa
  danh sách chất lượng của tập cùng phụ đề từng chất lượng.
- Ảnh: `uploads/movie-images/…`, phụ đề: `uploads/movie-subs/…` — phục vụ qua `/uploads/…`.
- Cả hai bảng được **tự tạo khi máy chủ khởi động** (`ensureCustomMoviesCompatibility`), không cần
  chạy SQL bằng tay. Nếu cột `qualities` chưa có, máy chủ tự thêm.

## 5. Ghi chú kỹ thuật
- Ảnh tải lên được kiểm tra bằng **magic bytes** (chỉ nhận JPEG/PNG/WebP) và giới hạn 8MB.
- Link phụ đề ngoài được máy chủ tải về, đổi sang **WebVTT** rồi lưu thành tệp — AVPlayer chỉ đọc
  WebVTT, và cách này giữ phụ đề chạy đúng tiến trình kể cả khi tua.
- Phim thủ công xuất hiện ở **trang 1** của danh sách/tìm kiếm/trang chủ, xếp theo thời gian cập nhật.
- Lượt xem thật tăng khi có người mở trang chi tiết phim đó.
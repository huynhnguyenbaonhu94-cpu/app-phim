# Hợp đồng API cho tính năng bình luận

App đã có sẵn toàn bộ phần bình luận ở phía client. Phần còn lại là ba procedure tRPC
trên máy chủ (`https://cungcapicloud.id.vn`). Cho tới khi chúng tồn tại, app tự chuyển
sang **lưu bình luận trên thiết bị** để tính năng vẫn dùng được, và tự quay về chế độ
máy chủ ngay khi ba procedure dưới đây trả lời được — không cần sửa gì thêm ở client.

## 1. Đọc danh sách bình luận

```
GET /api/trpc/cinema.comments?input={"json":{"slug":"so-ly"}}
```

Tên procedure: **`cinema.comments`** (query, không cần đăng nhập).

Sau khi tRPC bọc lại, `result.data.json` có thể là **mảng trần** hoặc một object bọc:

```jsonc
// chấp nhận cả hai dạng này
[ { …comment… }, { …comment… } ]
{ "items": [ { …comment… } ] }     // hoặc "comments" / "data" / "list" / "results" / "rows"
```

Một bình luận:

```jsonc
{
  "id": "c_1024",            // chuỗi hoặc số đều được
  "parentId": null,          // null/không có = bình luận gốc; có giá trị = trả lời
  "content": "Phim hay lắm!",
  "createdAt": "2026-10-08T11:02:00.000Z",   // ISO, hoặc epoch giây/mili giây
  "userName": "Nguyễn A",   // hoặc "authorName" / "author" / "user": { "name": … }
  "userRole": "admin",       // hoặc "role"; dùng để gắn huy hiệu quản trị
  "userId": 12,              // hoặc "authorId"; dùng để biết bình luận của mình
  "isMine": false            // tuỳ chọn; nếu không có, app tự so userId/tên
}
```

App đọc được nhiều cách đặt tên trường nên không cần đổi tên cột trong database:

| Ý nghĩa | Các tên app chấp nhận |
| --- | --- |
| id | `id`, `commentId`, `comment_id`, `_id` |
| trả lời cho | `parentId`, `parent_id`, `replyTo`, `parentCommentId` |
| nội dung | `content`, `text`, `body`, `message` |
| tên người gửi | `userName`, `user_name`, `authorName`, `author`, `name`, `fullName`, `user.name` |
| vai trò | `role`, `userRole`, `authorRole`, `user.role` |
| id người gửi | `userId`, `authorId`, `user.id` |
| email | `email`, `userEmail`, `authorEmail`, `user.email` |
| thời gian | `createdAt`, `created_at`, `time`, `date`, `timestamp` |

Một phần tử sai định dạng sẽ bị bỏ qua, những bình luận còn lại vẫn hiện.

## 2. Gửi bình luận

```
POST /api/trpc/cinema.addComment
Content-Type: application/json
Body: {"json":{"slug":"so-ly","content":"Phim hay lắm!","parentId":null}}
```

- **Bắt buộc đăng nhập** (cookie phiên như các procedure `account.*` hiện tại). Chưa
  đăng nhập thì trả lỗi — app hiện nút "Đăng nhập để bình luận" nên người dùng không
  gọi được procedure này khi chưa có phiên.
- `parentId` là id bình luận gốc khi người dùng bấm "Trả lời"; bỏ trống khi bình luận mới.
- Trả về bình luận vừa tạo theo đúng cấu trúc ở mục 1 (đặt trực tiếp hoặc trong
  `{ "comment": … }` / `{ "item": … }` / `{ "data": … }`). App dùng bản trả về để thay
  thế bình luận tạm đang hiển thị, nên **nên trả về `id`, `createdAt`, `userName`,
  `userRole`**.

## 3. Xoá bình luận

```
POST /api/trpc/cinema.deleteComment
Content-Type: application/json
Body: {"json":{"slug":"so-ly","id":"c_1024"}}
```

Trả về `{ "success": true }`. Chỉ cho phép chủ bình luận (hoặc quản trị viên) xoá.
Nếu xoá thất bại, app khôi phục bình luận về chỗ cũ và hiện thông báo, nên không có
chuyện nội dung biến mất im lặng.

## 4. Huy hiệu quản trị

App gắn huy hiệu "ADMIN" (tên in đậm màu xanh + tích xanh động) khi **một trong hai**
điều kiện đúng:

1. `userRole` (hoặc `role`) của bình luận chứa `admin`, `quantri` hoặc `moderator` — cách
   nên dùng, vì nó hoạt động cho mọi bình luận trong danh sách.
2. Email người gửi nằm trong danh sách dự phòng ở
   `Sources/Cinemora/Models/CommentModels.swift`:

   ```swift
   static let fallbackAdminEmails: Set<String> = []   // thêm email của bạn vào đây
   ```

   Cách này chỉ cần thiết nếu backend chưa kịp trả `role`.

Tài khoản đã đăng nhập cũng có `role` trong `auth.me` / `auth.login`; nếu trường đó có
giá trị `admin`, bình luận do chính bạn gửi sẽ mang huy hiệu ngay cả ở chế độ lưu trên
thiết bị.

## 5. Nhịp làm mới và giới hạn

- Trong lúc trang chi tiết phim còn mở, app gọi `cinema.comments` **mỗi 7 giây** và một
  lần nữa khi app quay lại tiền cảnh. Nếu sau này có endpoint SSE cho bình luận, chỉ cần
  thay vòng làm mới đó trong `State/CommentsStore.swift`.
- Nên giới hạn độ dài `content` (ví dụ 1–2000 ký tự), chặn gửi trùng trong vài giây và
  giới hạn số bình luận mỗi tài khoản mỗi ngày để tránh spam.
- App gửi bình luận theo kiểu lạc quan: hiện ngay, rồi thay bằng bản của máy chủ. Vì vậy
  trả lỗi rõ ràng (kèm `message`) sẽ giúp người dùng biết vì sao bình luận bị đánh dấu
  "Gửi lỗi" và có thể thử lại.
## 6. Cách nhanh hơn nếu bạn muốn chạy trên hosting cPanel

Nếu không muốn đụng vào backend hiện tại, dùng luôn gói **`cpanel-comments/`** (nằm
cạnh thư mục này trong file zip): upload lên hosting cPanel, tạo một tên miền phụ, rồi
điền `COMMENTS_API_BASE_URL` trong `project.yml` và build lại app.

Dịch vụ PHP đó:

- trả về **đúng định dạng tRPC** như mô tả ở mục 1–3 phía trên, nên app không cần biết
  bình luận đang chạy ở đâu;
- tự xác thực người dùng bằng cách hỏi `auth.me` của backend chính với cookie phiên
  được chuyển tiếp — không cần đồng bộ database người dùng, và vai trò quản trị luôn
  khớp với tài khoản thật;
- lưu bình luận bằng SQLite (mặc định) hoặc MySQL, có sẵn chống spam, kiểm tra độ dài,
  và luật xoá (chủ bình luận hoặc quản trị viên).

Hướng dẫn từng bước nằm trong **`cpanel-comments/README.md`**.

Hai cách này dùng chung một hợp đồng, nên có thể bắt đầu bằng gói PHP rồi chuyển sang
procedure trong backend chính sau — chỉ cần đổi `COMMENTS_API_BASE_URL` về rỗng.
## 7. Cách gọn nhất: backend tRPC trong zip đã có sẵn ba procedure

`server/` và `drizzle/` trong file zip **đã được thêm phần bình luận**, nên chỉ cần
deploy backend như bình thường là xong — bảng tự tạo khi máy chủ khởi động, không phải
chạy migration tay:

| Thay đổi | Tệp |
| --- | --- |
| Bảng `movie_comments` (+ chỉ mục) | `drizzle/schema.ts` |
| Hàm thêm/đọc/xoá + tạo bảng khi khởi động | `server/db.ts` (`ensureMovieCommentsCompatibility`) |
| Ba procedure `cinema.comments`, `cinema.addComment`, `cinema.deleteComment` | `server/routers.ts` |
| Giới hạn 20 bình luận mỗi phút cho mỗi tài khoản | `server/securityRateLimit.ts` |

Đã kiểm: `tsc --noEmit` sạch (chế độ strict, gồm cả `server/**`), và 14/14 test cũ vẫn
pass. Khi dùng cách này, để trống `COMMENTS_API_BASE_URL` — bình luận chạy chung máy chủ
chính, đồng bộ thật giữa mọi người dùng.
# Triển khai subtitle preferences và kích thước media

Migration SQL: `drizzle/0011_subtitle_preferences_chat_dimensions.sql`. Khi triển khai thủ công trên cPanel, chạy migration một lần sau khi sao lưu database. Migration Drizzle thông thường dùng `ADD COLUMN` và không idempotent; startup guard trong `server/db.ts` tự thêm các cột còn thiếu, nên máy chủ cPanel cũ có thể chỉ cập nhật mã và restart. Hai cơ chế cùng hỗ trợ: startup guard bỏ qua cột đã tồn tại.

`users.subtitlePreferences` là `MEDIUMTEXT NULL`, chứa JSON preferences. `special_chat_attachments.mediaWidth`/`mediaHeight` là `INT NULL`; dữ liệu/tin nhắn cũ tiếp tục trả `null`.

# Sửa phụ đề PiP iOS

PiP vẫn có thể hiện phụ đề nếu phụ đề là track mà AVPlayer đọc được từ media. Lớp phụ đề SwiftUI tự vẽ của Cinemora chỉ nằm trên giao diện app nên không tự xuất hiện trong cửa sổ PiP của iOS. Một số ứng dụng khác phát track phụ đề native HLS hoặc gắn phụ đề trực tiếp vào hình.

Nguyên nhân trong luồng cũ: master playlist khai báo URL `.vtt` thô ngay trong `EXT-X-MEDIA:TYPE=SUBTITLES`. HLS yêu cầu URI này trỏ đến một subtitle Media Playlist. Một số nguồn còn trả về master playlist; master không thể được đặt trực tiếp làm URI của một variant khác.

Bản sửa tạo endpoint `/api/cinema/subtitle-media.m3u8` bao quanh file WebVTT thành một playlist HLS VOD, và nếu nguồn video là master playlist thì gắn track phụ đề vào từng variant thật. Track app đang chọn vẫn được chọn trên `AVPlayerItem`; sub tự vẽ trong Cinemora tiếp tục dùng ở chế độ xem thường.

## Cập nhật cPanel

Tải source backend mới lên thư mục dự án Cinemora, cài dependencies nếu cần, chạy build như thường lệ và restart ứng dụng Node trong cPanel. Sau khi backend được cập nhật, app iOS hiện có sẽ gọi endpoint mới khi yêu cầu playlist PiP; không cần build lại IPA chỉ vì bản sửa này. Nếu đang dùng IPA cũ chưa có lựa chọn native track, cần build từ source iOS mới nhất.

Đã kiểm tra bằng `pnpm run check`, `pnpm test` (34/34 test) và `pnpm run build`.

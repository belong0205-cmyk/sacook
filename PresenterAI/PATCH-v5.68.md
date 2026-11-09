# SA Cook Assistant 5.68 — không mất chữ cuối khi bấm Space

- Space chốt giao diện ngay nhưng giữ một đuôi âm thanh thích ứng để nhận đủ chữ cuối.
- Nếu âm thanh đã im đủ lâu, ứng dụng không cộng thêm độ trễ không cần thiết.
- Nếu frame hoặc bản nhận diện cuối đến trễ, ứng dụng tự chờ trong giới hạn ngắn thay vì bắt người dùng đợi một giây rồi mới bấm.
- Sửa cả luồng có timestamp và luồng dự phòng không có timestamp trên macOS.
- Đồng bộ cơ chế chống cắt chữ cuối cho AudioWorklet và MediaRecorder trên Windows.

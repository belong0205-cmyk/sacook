# SA Cook Assistant 5.75 — Sửa âm thanh hệ thống không có tín hiệu

- Bổ sung cả `NSScreenCaptureUsageDescription` và `NSAudioCaptureUsageDescription` mà macOS mới yêu cầu cho ScreenCaptureKit và quyền thu âm thanh hệ thống riêng.
- Không tiếp tục nghe ngay sau lần cấp quyền đầu tiên; hướng dẫn mở lại app để quyền có hiệu lực đầy đủ.
- Thu âm thanh hệ thống ở 48 kHz stereo theo cấu hình khuyến nghị của Apple, sau đó dùng chung pipeline nhận diện hiện có.
- Phân biệt rõ ba trạng thái: chưa nhận buffer, đã kết nối nhưng đang im lặng, và có âm thanh.
- Hiện cảnh báo ngay trên nút nghe nếu sau bốn giây ScreenCaptureKit vẫn chưa gửi dữ liệu.

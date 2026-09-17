# Private Screen cho macOS

Ứng dụng ghi chú riêng tư đặt `NSWindow.sharingType = .none`, yêu cầu macOS không đưa nội dung cửa sổ vào các API chụp/chia sẻ màn hình thông thường.

## Mở ứng dụng

Chạy `./build-app.sh`, sau đó mở `dist/Private Screen.app`.

## Cách kiểm tra với Google Meet

1. Vào một cuộc họp thử bằng hai tài khoản hoặc nhờ một người kiểm tra.
2. Chọn chia sẻ toàn bộ màn hình.
3. Mở Private Screen và nhập nội dung không nhạy cảm để thử.
4. Chỉ dùng cho dữ liệu riêng tư sau khi phía người xem xác nhận cửa sổ bị trống/ẩn.

## Giới hạn quan trọng

Đây là yêu cầu bảo vệ dành cho chính cửa sổ Private Screen, không che được cửa sổ của ứng dụng khác. Trình duyệt hoặc phiên bản macOS dùng cơ chế ghi màn hình khác có thể vẫn thu được cửa sổ. Biện pháp chắc chắn nhất vẫn là chia sẻ riêng một tab/cửa sổ thay vì toàn bộ màn hình.

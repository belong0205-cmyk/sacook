# SA Cook Assistant 5.69 — Full không lặp lại Short

- Full chỉ chứa các ý bổ sung để nói tiếp sau Short.
- Prompt mới cấm lặp, diễn đạt lại hoặc chép nguyên câu Short vào Full.
- Hậu xử lý tự loại câu Short nếu model vẫn đặt lại ở đầu Full.
- Áp dụng đồng bộ cho E, V, dữ liệu cục bộ và câu trả lời AI.
- Nếu không có ý bổ sung thật sự, ứng dụng chỉ hiện Short thay vì tạo một Full giống hệt.
- Cửa sổ macOS tự co theo vùng hiển thị và hỗ trợ kích thước nhỏ 720 × 520.
- Khóa hoàn toàn cuộn ngang; câu hỏi và câu trả lời luôn xuống dòng trong từng cột E/V.
- Bỏ bóng đen quanh chữ để không còn hiện tượng chữ chồng hoặc đổ bóng bên dưới.
- Bỏ bo khung và giảm padding để hai cột dùng gần như toàn bộ diện tích cửa sổ.
- Thay thanh dưới bằng một hàng trên rất gọn: `V`, `E`, `Bắt đầu nghe`, `•••`.
- Nguồn âm thanh, chốt Space và toàn bộ tuỳ chỉnh được gom vào menu `•••` ở góc trên phải.
- Menu `•••` vẫn hiển thị trạng thái nghe và tín hiệu âm thanh theo thời gian thực.
- Áp dụng lại cờ chống capture cho mọi cửa sổ, panel và hộp thoại ở mỗi lần hiện/kích hoạt (tương thích best-effort với các cơ chế chia sẻ cũ của macOS).

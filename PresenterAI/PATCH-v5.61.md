# SA Cook Assistant 5.61 — V ổn định và Space mượt hơn

- Sửa cache V/E bị đọc ở `v16` nhưng lưu nhầm sang `v15`, khiến câu trả lời tiếng Việt không được dùng lại sau khi mở app.
- Khóa ngôn ngữ đầu ra theo từng bảng: V luôn định dạng tiếng Việt, E luôn định dạng tiếng Anh.
- Chuyển việc xếp hạng dữ liệu và dựng ngữ cảnh AI khỏi luồng giao diện để bấm Space không làm xuất hiện vòng xoay chờ.
- Tái sử dụng phần lịch sử đã dựng và không dựng lại các khung lịch sử ẩn sau mỗi trạng thái tải.

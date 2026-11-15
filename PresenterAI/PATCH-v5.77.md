# SA Cook Assistant 5.77 — System Audio và thuật ngữ Pháp

- Sửa lỗi Core Audio đã nhận packet nhưng buffer đích có kích thước bằng 0 nên âm thanh bị bỏ toàn bộ.
- Đặt đúng độ dài PCM trước khi sao chép cho cả Core Audio và ScreenCaptureKit.
- Tự chuyển sang ScreenCaptureKit nếu Core Audio không gửi buffer, ghi nhớ nguồn hoạt động cho lần mở sau; vẫn chỉ nghe âm thanh hệ thống, không dùng micro.
- Nâng nhận diện thuật ngữ nấu ăn tiếng Pháp bằng 146 từ trong tài liệu, nhóm từ ưu tiên và các biến thể phát âm thường bị nghe sai.
- Đã test trực tiếp trên máy: app nhận được câu hỏi từ System Audio và tạo song song đáp án V + E.
- Thêm kiểm thử hồi quy cho PCM stereo, giới hạn Apple Speech 100 cụm và các biến thể phát âm Pháp.


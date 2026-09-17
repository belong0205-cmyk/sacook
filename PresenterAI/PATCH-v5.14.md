# v5.14 — SPACE và AUTO xử lý độc lập

Hai phần chỉ dùng chung nguồn âm thanh/phiên âm đầu vào, API key và tài liệu tra cứu. Mỗi phần có bộ đệm, cách chốt câu, dòng đang nghe, hàng đợi AI, bộ nhớ đệm đáp án và lịch sử riêng. Chạy hai phiên nhận dạng âm thanh đồng thời không được dùng; sự độc lập nằm ở toàn bộ xử lý phía sau nguồn âm thanh.

## Nguyên nhân và thay đổi

Ở v5.13, AUTO đợi toàn bộ âm thanh im lặng và xét cả đoạn đang nghe như một câu. Lời dẫn hoặc câu trả lời nối tiếp khiến câu hỏi hoàn chỉnh bị trộn vào một đoạn dài; phần kiểm tra khớp dữ liệu có thể giữ nó lại. Hai bảng còn dùng chung hai lượt gọi AI và gộp yêu cầu cùng câu hỏi.

v5.14 nhận từng câu hỏi trong chuỗi lời nói. Bộ kiểm tra chạy mỗi 100 ms, kể cả khi không có bản phiên âm mới. Một câu có dấu kết thúc được giữ ổn định khoảng 350 ms trước khi gửi; câu không có dấu kết thúc được xét sau khoảng 1,2 giây ổn định. Đây là cấu hình chốt phiên âm, không phải cam kết thời gian trả lời AI.

Đã kiểm thử hai chuỗi liên tục không dấu câu: “How do you ensure quality and consistency in your work I follow recipes…” và “How do you handle pressure during busy hours I stay calm…”. AUTO lấy câu hỏi trước phần trả lời mà không chờ toàn bộ đoạn im lặng. Các câu có “List… may define…”, “Describe how…”, hai câu hỏi về dao và “Define julienne” vẫn được giữ đúng cấu trúc.

SPACE không gọi lại, xóa hay thay đổi bộ hẹn giờ của AUTO. AUTO không tiêu thụ chữ trong vùng SPACE. Hai hàng đợi AI có hai lượt xử lý riêng mỗi bên; cùng một câu ở hai bảng cũng tạo hai yêu cầu riêng. Kết quả được gắn đúng hàng, không chuyển sang bảng còn lại. Vì yêu cầu AI được tách, cùng một câu gọi AI ở cả hai bảng có thể phát sinh hai lượt API.

SPACE nhận phần chữ đến muộn theo mốc âm thanh khi có thông tin thời gian dùng được. Nếu phiên âm tạm không có mốc hợp lệ, nó chốt đúng đoạn chữ đang hiển thị thay vì dùng các mốc bằng 0 và làm mất những câu sau. Trong trường hợp thiếu mốc, không thể cam kết bổ sung chính xác những chữ chưa xuất hiện tại lúc bấm Space.

Giao diện có hai dòng đang nghe, hai nút Xoá, hai nút Thử lại và công tắc tạm dừng AUTO riêng. Tạm dừng AUTO không dừng SPACE.

## Kiểm chứng

- 61 kiểm tra bộ nhận câu AUTO: liên tục hỏi–đáp, lời dẫn, chữ bị sửa, câu ghép, câu ngắn, thiếu mốc âm thanh, chuyển phiên và bật/tắt.
- 49 kiểm tra tích hợp hai luồng với bộ nhận câu thật: Space/AUTO không xóa trạng thái của nhau, chữ cuối đến muộn, chốt liên tiếp, thiếu mốc và chuyển phiên nhận âm thanh.
- 44 kiểm tra hàng đợi riêng; 67 kiểm tra tích hợp hàng đợi và phản hồi API.
- 36 kiểm tra bộ đệm thiếu mốc; 17 kiểm tra mốc âm thanh.
- 2.900 assertions về chuẩn hóa, câu hỏi và dữ liệu; 8 bài kiểm tra tính toàn vẹn dữ liệu.
- Tất cả đạt trong lần đóng gói. Chữ ký và ZIP sau giải nén đã được kiểm tra.
- Đã mở ứng dụng thật, xác nhận v5.14 và giao diện hai bảng riêng. Đã khởi động nghe BlackHole 2ch thành công; lúc kiểm tra đầu vào đang im lặng.

Các bài kiểm tra phiên âm sử dụng sự kiện mô phỏng, API dùng phản hồi giả lập. Chưa đo độ chính xác với bản ghi âm giọng nói thực tế trong lần này. Không có cam kết nhận dạng chính xác tuyệt đối.

Một [báo cáo trên Apple Developer Forums](https://developer.apple.com/forums/thread/785389) mô tả thời gian trong bản phiên âm tạm có thể chưa chính xác; đây là báo cáo của nhà phát triển, không phải bảo đảm của Apple. Bản vá kiểm tra trực tiếp dữ liệu nhận vào và có đường xử lý không phụ thuộc vào mốc thời gian cho AUTO.

Build/kiểm thử/đóng gói lại: `/bin/zsh PresenterAI/Scripts/release.sh`. Gói cập nhật cục bộ: `outputs/SA-Cook-Assistant-v5.14.zip`. Không cần người dùng tải hoặc chép app thủ công.

# Bản vá v5.13 (build 63)

## Lỗi đã xác minh

Đã chạy lại mã v5.12 được giữ trong `Tests/main-v5.12.baseline.m` và tái hiện 6 lỗi: làm hỏng “julienne” dù từ đã đúng; cắt câu ở chữ “define”; tách sai một câu thành hai; bỏ qua “Which” khi thiếu dấu hỏi; chỉ giữ câu cuối trong hai câu hỏi; thay câu nghe được bằng câu gần giống trong database.

Rà soát luồng âm thanh còn phát hiện việc cộng dồn bản nhận diện tạm sau mỗi lần im lặng, khoảng trống 350 ms khi khởi động lại nhận diện, và AUTO đánh dấu câu đã xử lý trước khi yêu cầu AI thực sự được gửi.

## Hành vi mới

- Space chốt mốc âm thanh. Kết quả đến muộn được lọc theo thời gian phát âm: nhận chữ trước mốc, loại lời nói sau mốc. Chờ tối đa 1,2 giây để nhận nốt chữ cuối; không khởi động lại nhận diện khi bấm Space.
- AUTO có mốc đã xử lý riêng. Space không xóa vùng nghe, bộ hẹn giờ hoặc câu trả lời của AUTO. AUTO chờ tín hiệu ngừng nói và bản nhận diện ổn định, tránh tìm đáp án trên từng bản nhận diện tạm.
- Giữ nguyên câu hỏi nghe được, chỉ sửa các biến thể thuật ngữ đã biết. Không tự đổi thành câu khác trong database. Các câu ghép được giữ đầy đủ.
- Dùng đáp án tại máy khi khớp đủ chắc chắn; trường hợp chưa đủ căn cứ được chuyển cho AI cùng câu hỏi gốc và tài liệu liên quan. Giảm việc dùng đáp án chỉ giống vài chữ hoặc khác ý phủ định.
- Mỗi yêu cầu AI gắn với đúng câu hỏi và đúng bảng. Yêu cầu đang chờ được xếp hàng, kết quả đến trễ cập nhật đúng lịch sử. Cùng một câu trong AUTO và SPACE có thể dùng chung một yêu cầu mạng.
- Bộ nhớ đệm đáp án v5 cũ không được dùng lại vì có thể đã lưu đáp án theo câu bị nhận diện sai. API key đã lưu không bị thay đổi.
- Sửa nhãn nhóm ở ranh giới dữ liệu và tạo chỉ mục theo thứ tự xác định. Chữ ký và file ZIP được kiểm tra sau khi giải nén trước khi công bố cho nút Update.

## Kết quả kiểm tra

| Nhóm kiểm tra | Kết quả |
|---|---:|
| Tái hiện lỗi trên mã v5.12 | 6/6 lỗi tái hiện được |
| Chuẩn hoá thuật ngữ, câu hỏi và đối chiếu dữ liệu | 2.900 assertions đạt |
| Mốc thời gian / cập nhật bản nhận diện | 17 checks đạt |
| Tích hợp Space / AUTO và chữ cuối đến muộn | 37 checks đạt |
| Hàng đợi AI, kết quả lệch thứ tự và lỗi API | 51 assertions đạt |
| Tính toàn vẹn dữ liệu | 8 tests đạt |

Ứng dụng nạp 1.187 cặp hỏi–đáp và 216 gợi ý thuật ngữ. Kiểm tra dữ liệu nguồn có 965 ID câu hỏi, không có ID bị ghép sang câu khác; 959 bản ghi JSON được đối chiếu với đáp án đúng ID. Các câu về cultural identity, cleaning/sanitising và hai loại dao có dữ liệu phù hợp.

Trong lần chạy đóng gói, tra cứu 11 câu ví dụ mất trung bình 5,77 ms, lớn nhất 15,03 ms. Đây chỉ là thời gian tra cứu nội bộ, không phải thời gian từ âm thanh đến đáp án.

Kiểm thử âm thanh dùng các sự kiện nhận diện và mốc thời gian mô phỏng; chưa đo độ chính xác trên bản ghi giọng nói thực tế qua BlackHole. Kiểm thử API dùng phản hồi giả lập, không sử dụng key thật hay phát sinh phí. Apple Speech có thể vẫn nhận sai trong tiếng ồn, giọng khó nghe hoặc khi kết quả đến quá muộn; AI còn phụ thuộc mạng và tài khoản API. Không có cam kết chính xác tuyệt đối.

## Chạy lại

`/bin/zsh PresenterAI/Scripts/test.sh`

Build, kiểm thử, ký và đóng gói: `/bin/zsh PresenterAI/Scripts/release.sh`.

Trên máy này, nút Update tìm thấy `outputs/SA-Cook-Assistant-v5.13.zip`; không cần người dùng tải hay chép app thủ công. Bản vá hiện được phân phối cục bộ trên máy, chưa công bố GitHub Release.

Đã kiểm tra trực tiếp luồng Update: ứng dụng v5.12 nhận ra v5.13, cài đặt và mở lại thành công. Giao diện sau cập nhật hiển thị v5.13, nguồn BlackHole 2ch và bộ nhớ 1.187 câu / 1.449 biến thể / 216 thuật ngữ. Ứng dụng đang ở trạng thái chờ Bắt đầu nghe.

## Tài liệu đối chiếu

Mốc từng đoạn phát âm sử dụng timestamp/duration theo [Apple SFTranscriptionSegment](https://developer.apple.com/documentation/speech/sftranscriptionsegment). Luồng âm thanh liên tục theo [SFSpeechAudioBufferRecognitionRequest](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest). Phần AI ghép các khối output_text và tách lỗi khỏi đáp án theo [OpenAI text generation](https://developers.openai.com/api/docs/guides/text) và [API error codes](https://developers.openai.com/api/docs/guides/error-codes).

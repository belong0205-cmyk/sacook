# SA Cook Assistant — Project Memory

Last updated: 2026-11-15 (Asia/Ho_Chi_Minh)

## Product goal

- macOS and Windows presenter assistant for SA Cook interviews.
- Capture system audio without microphone, transcribe culinary questions, and show concise V/E answers in parallel after Space.
- Use local SA Cook data and per-user profile/menu data; English answers target B2.
- Compact translucent overlay, hidden from screen sharing, with in-app updates.

## Current stable state

- Release: `v5.77.0`, commit `585348b`, branch `main`.
- Repository: `belong0205-cmyk/sacook`.
- macOS release: https://github.com/belong0205-cmyk/sacook/releases/tag/v5.77.0
- Windows channel: `v5.77-windows-preview.1`.
- Direct machine test succeeded: System Audio recognized “Identify six Australian native ingredients?” and produced both V and E answers.
- System-audio fix: correct PCM frame length for Core Audio and ScreenCaptureKit; if Core Audio supplies no buffer, perform a clean restart and remember ScreenCaptureKit compatibility mode. No microphone is used in this mode.
- French speech data: 146 culinary terms from `Thuat-ngu-tieng-Phap-SA-Cook.docx`, shared by macOS and Windows.
- French recognition uses Apple contextual strings (maximum 100), N-best alternatives, pronunciation post-correction, and cached regular expressions for low latency.
- Latest tests: macOS recognition 10,295 assertions / 0 failures; complete macOS and Windows suites passed; release checksums verified.

## Active flows

- Leader: current thread `Ẩn màn hình khi chia sẻ`.
- Audio research: thread `Nghiên cứu âm thanh`, ID `01a1dcd8-169c-7de3-9aad-f72fc492b128`, assigned to research low-latency French culinary speech accuracy. It must report evidence and tests, and must not publish or overwrite the main source without leader approval.
- Designer flow exists separately; integrate changes only after leader review.

## Working rules

- Leader owns integration, regression testing, version bump, packaging and GitHub release.
- Other flows research or work in isolated checkouts; do not edit the same main checkout concurrently.
- Preserve working Space behavior and screen-share protection.
- Never hardcode or commit API keys. Store them only in the app's secure local storage.
- Keep user-facing progress concise; avoid repeating old history.
- Before release: run `./Scripts/build-all.sh`, verify sync/checksums, commit and push `main`, then run `./Scripts/publish-all.sh --skip-build`.

## Next likely work

- Review the report returned by `Nghiên cứu âm thanh`.
- Add pronunciation cases only when they are reproducible and covered by macOS + Windows tests.
- Prefer low-latency contextual hints and correction over enabling a blocking custom language model by default.

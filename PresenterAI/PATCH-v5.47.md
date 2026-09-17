# SA Cook Assistant 5.47

- Treats AUTO audio as a complete speaking turn instead of answering every short pause.
- Waits for all queued transcription work, merges repeated or referential follow-up questions, and sends one answer request for one linked turn.
- Keeps genuinely independent questions separate and answers them in order.
- Starts in accessory mode before the macOS event loop and retains `LSUIElement`, preventing a Dock icon from appearing after a full relaunch.

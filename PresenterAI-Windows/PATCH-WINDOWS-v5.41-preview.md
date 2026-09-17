# SA Cook Assistant — Windows Preview 5.41

Portable preview for Windows 10/11 x64.

- Captures Windows system audio directly; BlackHole is not required.
- Keeps AUTO and SPACE recognition independent, with separate answers and histories.
- Restarts audio capture before transcription so the app does not go deaf while waiting for the API.
- Uses `gpt-transcribe` with cookery and French culinary terminology as context.
- Uses 1,181 local/reference questions and 245 speech hints, then AI and optional web search when the local data is insufficient.
- Stores the OpenAI API key with Windows Secure Storage (DPAPI).
- Requests Windows capture exclusion for the presenter window.

This preview is unsigned, so Windows SmartScreen may show a warning. Extract the entire ZIP before running `SA Cook Assistant.exe`.

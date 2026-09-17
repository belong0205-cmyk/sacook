# SA Cook Assistant Windows Preview 5.45

- Removes the unsupported `gpt-live-transcribe` file request that added a failed network round trip before every fast transcription.
- Uses `gpt-transcribe` first, with `gpt-4o-transcribe` as the supported fallback.
- Sends up to 100 culinary keyword hints for better French, safety and knife terminology.
- Recognises and removes natural interviewer lead-ins before submitting an AUTO question.
- Retains the shared B2 answer policy from 5.44.


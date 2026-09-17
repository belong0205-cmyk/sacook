# SA Cook Assistant Windows Preview 5.55

- Use languages[] for gpt-transcribe and language for the legacy fallback model.
- Retry the AUTO endpoint timer if the transcription queue is busy, and rearm it when the queue drains.
- Empty transcripts no longer cancel a pending endpoint.
- Recognize short questions such as “What is stock?” and embedded phrases such as “How can we use a thermometer?”.
- Preserve incomplete questions for the next audio chunk.
- Disable text selection and Copy actions in reading panes; keep the arrow cursor.

Validated with runtime regression tests using controlled timers and mocked network responses. Live Windows audio capture still needs an on-device listening session.

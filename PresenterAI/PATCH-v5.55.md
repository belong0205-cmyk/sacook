# SA Cook Assistant 5.55

- Correct the transcription API language field for gpt-transcribe.
- Keep live AUTO question detection and natural-question fallback active when an API key is saved.
- Preserve current live words when a previous cloud transcription fails; ignore callbacks from older listening sessions.
- Keep the AUTO timer running during scroll/menu tracking and suppress identical consecutive submissions.
- Disable reading-pane selection and Copy actions; keep the arrow cursor.

Validation: reproduced five failing macOS integration checks before the fix; added regression coverage for cloud failure, stale sessions, natural phrasing with enhanced recognition, and the outgoing multipart request. Windows has runtime tests for busy queues, empty audio chunks, short questions, split questions, and API fallback.

The available historical source is 5.12, not 5.2. Tests use simulated transcript sequences and mocked requests; live BlackHole speech accuracy and account-specific API access still need a real listening session.

API schema reference: https://developers.openai.com/api/docs/guides/speech-to-text#add-transcription-context

# SA Cook Assistant 5.45

- Improves AUTO accuracy on macOS by transcribing completed audio turns with `gpt-transcribe` when a saved OpenAI key is available.
- Supplies culinary and French vocabulary as transcription keywords and keeps Apple Speech as an automatic fallback when the API is unavailable or out of quota.
- Restores the balanced v4-style Apple Speech vocabulary so safety, knife and workplace terminology is not displaced by too many variants of a few words.
- Recognises natural interviewer lead-ins such as “All right”, “Let me ask”, and “I'd like to know” without including them in the displayed question.
- Keeps AUTO and SPACE independent. SPACE continues to use its timestamped Apple Speech path and does not wait for AUTO transcription.
- Retains the shared B2 answer policy from 5.44.


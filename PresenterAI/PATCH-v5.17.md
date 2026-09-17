# SA Cook Assistant 5.17 (build 67)

## AUTO multipart-question patch

- When one speaking turn contains two or more detected questions, AUTO waits for the trailing part for a short merge window (about 0.65 seconds) instead of answering the first part immediately.
- Questions from the same turn are kept verbatim, shown on separate lines, and sent as one AI request.
- The AI receives a separate local-data context for each question and is instructed to answer every part in order with numbered answers.
- A recognition-task rollover remains a real boundary, so questions from separate turns are not accidentally merged.
- Duplicate candidate text in one turn is removed before synthesis.
- SPACE remains independent and unchanged.

## Validation

- AUTO detector regressions cover punctuated, unpunctuated, timed and untimed two-question turns.
- Integration tests verify one combined AUTO request, exact ordering, no replay, and separation across recognition-task rollovers.
- Recognition/data tests verify that a multipart turn bypasses a misleading single local match and receives per-part reference sections.
- Existing answer-lane, SPACE, UI and source-data suites remain enabled.

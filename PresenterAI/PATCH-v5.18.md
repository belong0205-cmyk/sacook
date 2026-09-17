# SA Cook Assistant 5.18 (build 68)

## Context-aware AUTO follow-ups

- AUTO recognises referential follow-ups such as “What are the ingredients?”, “What do you have?”, and questions containing “that”, “this”, “those”, or “them”.
- For those questions only, AUTO supplies up to three recent AUTO exchanges as conversational context. It includes both previous questions and completed answers, so a vague immediately previous question can still lead back to an earlier explicit dish or topic.
- The newly heard question remains the only question shown in the large panel. Hidden context is used solely for synthesis and does not replace the evidence heard by the user.
- Context-dependent questions always use one AI synthesis with context-aware local reference retrieval instead of accepting a misleading generic local match.
- Explicit questions such as “What ingredients are used in a mirepoix?” and “What do you have in your menu?” remain self-contained and do not inherit an unrelated topic.
- Context-aware cache keys include the recent exchange, preventing an answer about one dish from being reused for the same vague wording about another dish.
- The existing v5.17 same-turn multipart merge remains enabled; SPACE remains independent.

## Validation

- The supplied style of follow-up is covered by offline recognition tests.
- Tests verify the exact current question stays visible, previous question and answer reach synthesis, vague/self-contained classification, context-specific cache behavior, and answer attachment to the correct record.
- Existing AUTO endpoint, answer-lane, SPACE, UI and source-data suites remain enabled.

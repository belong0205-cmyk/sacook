# SA Cook Assistant 5.43

- Keeps the transparent, compact two-lane AUTO and SPACE interface unchanged.
- Uses the same shared feature manifest, UI tokens, and answer policy as the Windows edition.
- Prefers CEFR B1 English and uses B2 only when B1 is not clear enough, with no more than 30 spoken words per question.
- Simplifies both instant local answers and AI answers without another API request or added delay.
- Preserves necessary culinary and French terms, temperatures, negation, and numbered multi-question answers.
- Starts a new answer-cache namespace so older verbose answers are not reused.
- The updater now accepts only the exact macOS ZIP for a stable release, with a safe exact legacy filename fallback.

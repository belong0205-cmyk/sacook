# SA Cook Assistant 5.56

- AUTO waits about one second after the last transcript change to include linked follow-up questions. Later clarifications guide one answer; distinct subjects are not erased by fuzzy deduplication.
- Ignore late cloud transcripts for already committed audio, avoiding repeated questions from two recognizers. SPACE remains independent.
- Add **••• → Hồ sơ & menu riêng…**: name, restaurant, address, menu ingredients/preparation, and actual experience. Each OS user keeps their own profile outside the app bundle; updates preserve it. Blank fields are never filled with invented personal facts. Profile content is sent to OpenAI as answer context, not uploaded to GitHub.
- macOS prepares and verifies the new bundle before quitting. It uses a writable per-user Applications folder when necessary, checks startup, retains the previous bundle and restores it on failure. Diagnostics: `~/Library/Logs/SA Cook Assistant/update.log`.
- Existing broken updaters cannot repair themselves before installing this version. A one-time manual replacement may be required on affected machines.

Validation: automated speech/answer/UI/profile regressions and simulated macOS installation/rollback. Real microphone/BlackHole conditions and remote machines still need user acceptance testing.

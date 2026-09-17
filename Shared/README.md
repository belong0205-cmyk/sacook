# Shared SA Cook contract

This folder is the source of truth for behaviour shared by the macOS and Windows apps.

- `answer-policy.txt` is copied into both application bundles and controls answer language, CEFR level, voice, and length.
- `feature-manifest.json` lists features that must be present on both platforms before a release.
- `ui-tokens.json` records the common two-lane overlay design. Platform-native audio capture remains separate.

Run `Scripts/build-all.sh` for a synchronized build. It builds the macOS data index first, copies that exact study index into Windows, and stops if the versions, policy, or packaged data do not match.

Run `Scripts/publish-all.sh` to build, verify, and publish both update channels together. Stable releases remain macOS-only and Windows uses a matching prerelease while legacy macOS clients still accept the first ZIP in a stable release.

Answers use clear B2 English with varied, natural vocabulary and useful detail. Necessary culinary and French terms remain unchanged. Each answer can show a Short version for speaking immediately and a Full version with enough detail to recover if the interviewer asks for more.

AUTO uses enhanced OpenAI audio transcription when a saved key is available. macOS keeps Apple Speech as an automatic no-network fallback; Windows keeps `gpt-4o-transcribe` as a supported API fallback. Both platforms send the same culinary vocabulary guidance and continue to keep AUTO separate from SPACE.

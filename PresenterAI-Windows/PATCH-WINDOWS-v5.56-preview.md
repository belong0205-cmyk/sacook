# SA Cook Assistant Windows 5.56 preview

- Brief AUTO grace period includes connected question fragments and waits when speech continues between recorder chunks. SPACE capture remains unchanged.
- **••• → Hồ sơ & menu riêng…** stores a personal name, restaurant, address, menu and experience under the Windows user's app data, outside the installed app. Updates preserve it; other users/machines have separate profiles. Supplied profile data is sent to OpenAI when generating answers, not to GitHub.
- Fix the HTTP 200 download failure when Electron omits the response URL. Both the requested URL and any reported redirect are checked, and release size/SHA-256 verification remains mandatory.
- Renaming a complete portable folder no longer blocks updates. A protected installation can relocate to a writable per-user app folder. The updater retains startup checks and rollback; errors appear in a dialog.
- On machines whose current Update button is broken, install this package once to receive the updater fix.

Validation: deterministic AUTO/profile/download tests (including HTTP 200 with an empty URL and rejection of corrupted bytes). Packaged for Windows x64 on macOS; an end-to-end update on a physical Windows machine has not been run here.

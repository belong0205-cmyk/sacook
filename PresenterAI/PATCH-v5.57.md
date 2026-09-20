# SA Cook Assistant 5.57 — one-box personal profile

- Replace the individual profile fields with one editable text area and **Chọn Word…**. Accept .docx, UTF-8 .txt and .md, up to 10 MB and 40,000 text characters. Imports append to the editor; nothing is applied until **Xử lý & lưu**.
- An active OpenAI API key is required for automatic extraction. Only on that explicit action, source text is sent to OpenAI to classify the person's name, restaurant, address, menu, actual experience and other relevant facts. Unsupported facts are left blank and unresolved conflicts are flagged.
- Save the selected facts separately from the original editable source. Both stay in this OS user's local profile and survive app updates. Shared study data and other installations are not modified. Only selected facts enter subsequent answer requests, with priority over generic personal examples.
- Existing 5.56 profiles migrate to the single editor automatically. Failure, malformed/truncated AI output or closing the editor before processing completes does not replace the previous profile.
- Word import reads paragraphs, tables, headers and footers; it does not execute macros, follow embedded instructions, load external XML entities or extract files to disk. Image-only/scanned documents, encrypted documents and old .doc files need conversion to plain text/.docx first.

Validation: shared synthetic Word fixtures on both platforms, extraction validation and profile-isolation regressions, native UI checks, and existing AUTO/SPACE suites. No real user document was submitted to an API during automated testing; factual extraction should be reviewed using “Xem dữ liệu đã chọn”.

Implementation uses the [official OpenAI Structured Outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs) to require and validate a consistent extraction structure before saving.

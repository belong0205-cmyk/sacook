# SA Cook Assistant Windows 5.57 preview

- **••• → Hồ sơ & menu riêng…** now has one text area, **Chọn Word…** and **Xử lý & lưu**.
- Paste text or import .docx/.txt/.md (10 MB and 40,000 text characters maximum). Import appends to the visible editor. Old .doc, password-protected or image-only documents require conversion first.
- Explicit processing uses the configured OpenAI API key to select personal facts, restaurant/menu details and genuine experience. Source instructions are treated as data, unknown facts stay blank and conflicts are flagged. Invalid/incomplete output does not replace the saved profile.
- Profiles remain separate for each OS user/installation and survive Update. The original editable source is retained locally but omitted from subsequent answer prompts. Selected personal facts take priority over generic study examples; the shared database is not overwritten.
- Click **Thông tin đã chọn lọc** to review what was extracted. Closing during processing cancels the request before saving.

Validation: synthetic Word/table/Unicode fixtures, malformed and oversized archive rejection, extraction validation, profile isolation and existing AUTO/SPACE tests. Packaged for Windows x64 on macOS; not tested end-to-end on physical Windows or with a real user document/API extraction.

The extraction schema follows [official OpenAI Structured Outputs documentation](https://developers.openai.com/api/docs/guides/structured-outputs).

# SA Cook Assistant 5.16 (build 66)

- Compact 1120×760 default window; tighter toolbar, single-line lane headers, smaller padding and a 38-point live-transcript area.
- AUTO and SPACE histories are visible by default, with their own 180-point scroll area and question count. History controls now sit above each history.
- Either history can still be collapsed independently. Answer text remains adjustable, bright, selectable and separate for each lane.
- Repeated answer refreshes no longer redraw unchanged history. When a new question is added while reading older history, the view retains its reading position.
- Recognition, audio endpoints, database matching and AI request logic are unchanged.

Validation: existing regression suites plus 873 native UI assertions passed. Offscreen fixtures checked at 1120×760 and 980×660 with long questions and answers, histories visible, and 20/26/40-point answer text.

This update does not add cross-launch history persistence. In-memory history is lost when the app restarts. Use `Scripts/release.sh --package-only` to prepare the Update package without replacing or restarting an active application session.

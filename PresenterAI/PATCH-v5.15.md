# SA Cook Assistant 5.15 (build 65)

## Reading-focused interface

- Two equally sized, separately labelled AUTO and SPACE cards. Each retains its own question, answer, live transcript, retry action and history.
- Answer area fills available window height instead of being fixed at 300 points. Histories start collapsed and open independently.
- Both answer panels use the same 26-point default system font. A− / A+ (or Command-minus / Command-equals) adjust 20–40 points; the setting is remembered on this Mac.
- Distinct QUESTION and ANSWER headings, brighter neutral text, comfortable paragraph/line spacing, and blue/mint lane accents.
- Long text wraps within its panel. A vertical scrollbar appears when needed. Same-question refreshes retain reading position; new questions return to the top.
- Listening, input source, font size, Update and AI key are grouped in the top toolbar. SPACE has a direct “Chốt câu” button; AUTO has its own recognition toggle.
- Secondary text remains readable, and histories no longer use dark text.

## Scope

This is a UI/readability update. It does not change audio endpoints, question detection, the independent answer queues, data matching, model requests or API credentials. It does not claim improved speech-recognition accuracy or network latency.

## Validation

- Existing timeline, AUTO detector, answer-lane, untimed-buffer, recognition, answer-queue/parser, SPACE integration and source-data regression tests.
- Native offscreen AppKit UI test: 980×660 and 1180×800 content sizes; 20/26/40-point text; long multipart questions and answers; wrapping and full document height; independent history visibility; equal typography; layout, scroll and contrast checks.
- Offscreen preview uses synthetic demonstration Q&A, without starting audio, accessing API keys or making model requests.
- Clean application build, code-signature verification and ZIP extraction verification are performed by Scripts/release.sh.

Readability references: [Apple Typography](https://developer.apple.com/design/human-interface-guidelines/typography) and [W3C contrast guidance](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html). These informed font hierarchy, adjustable sizing and contrast checks; this is not a claim of complete accessibility conformance.

## Update

The verified ZIP is placed in the app's existing local update directory. Use **Update** in the application; no manual download is required on this Mac. Publishing this package to GitHub is a separate action.

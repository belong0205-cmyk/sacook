# Presenter AI v5.19

- Keeps the bundled SA Cook Study database as the first, instant answer source.
- When no reliable local match exists, OpenAI may answer from general culinary knowledge and use web search for missing, niche, uncertain, or current facts.
- Uses the current Responses API `web_search` tool with low search context and at most one search call to reduce delay.
- Makes web references visible as clickable URLs whenever web search contributes to an answer.
- Corrects observed speech variants such as “Verseti” to “versatility” before retrieval.
- Clears the previous answer-cache generation so old “references do not provide” responses are not reused.
- Answers remain English-only and concise for stage use.

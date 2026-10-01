#!/usr/bin/env python3
"""Generate Vietnamese Q&A retrieval data from the canonical SA Cook dataset."""

import json
import sys
from pathlib import Path


def clean(value):
    return " ".join(str(value or "").split())


source = Path(sys.argv[1])
output = Path(sys.argv[2])
data = json.loads(source.read_text(encoding="utf-8"))
rows = []
for category in data.get("categories", []):
    category_name = clean(category.get("nameVi") or category.get("name"))
    for item in category.get("questions", []):
        question_en = clean(item.get("question"))
        question_vi = clean(item.get("questionVi") or question_en)
        answer_en = clean(item.get("answer"))
        answer_vi = clean(item.get("answerVi") or answer_en)
        if not question_en or not question_vi or not answer_en or not answer_vi:
            continue
        # Either spoken language can drive both output lanes. English source
        # rows already cover English -> English, so this sidecar supplies the
        # three cross-language/localised retrieval paths.
        rows.extend([
            {"category": category_name, "question": question_en, "answer": answer_vi, "targetLanguage": "vi"},
            {"category": category_name, "question": question_vi, "answer": answer_vi, "targetLanguage": "vi"},
            {"category": category_name, "question": question_vi, "answer": answer_en, "targetLanguage": "en"},
        ])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(rows)} Vietnamese Q&A rows -> {output}")

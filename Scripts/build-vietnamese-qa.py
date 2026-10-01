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
        question = clean(item.get("questionVi") or item.get("question"))
        answer = clean(item.get("answerVi") or item.get("answer"))
        if question and answer:
            rows.append({"category": category_name, "question": question, "answer": answer})
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(rows)} Vietnamese Q&A rows -> {output}")

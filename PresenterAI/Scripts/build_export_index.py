#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path


def parse(path):
    category = "Uncategorised"
    question = None
    answer_lines = []
    mode = None
    records = []

    def flush():
        nonlocal question, answer_lines
        if question and answer_lines:
            records.append({
                "category": category,
                "question": " ".join(question.split()),
                "answer": " ".join(" ".join(answer_lines).split()),
            })
        question = None
        answer_lines = []

    with open(path, encoding="utf-8") as source:
        for raw in source:
            line = raw.rstrip("\n")
            if line.startswith("CATEGORY: "):
                # The pending answer still belongs to the previous category.
                flush()
                category = line[len("CATEGORY: "):].strip()
                mode = None
            elif line.startswith("Q: "):
                flush()
                question = line[3:].strip()
                mode = "question"
            elif line.startswith("A: "):
                answer_lines = [line[3:].strip()]
                mode = "answer"
            elif line.startswith("   ") and not line.lstrip().startswith("(VI:"):
                if mode == "question" and question:
                    question += " " + line.strip()
                elif mode == "answer" and answer_lines:
                    answer_lines.append(line.strip())
    flush()

    # Prefer the longer answer when the export repeats the same question.
    unique = {}
    for record in records:
        old = unique.get(record["question"])
        if old is None or len(record["answer"]) > len(old["answer"]):
            unique[record["question"]] = record
    return list(unique.values())


def parse_handbook(path):
    records = []
    current_file = ""
    question = None
    answer_lines = []
    collecting = False

    def flush():
        nonlocal question, answer_lines, collecting
        if question and answer_lines:
            records.append({
                "category": current_file,
                "question": " ".join(question.split()),
                "answer": " ".join(" ".join(answer_lines).split()),
            })
        question = None
        answer_lines = []
        collecting = False

    with open(path, encoding="utf-8") as source:
        for raw in source:
            line = raw.rstrip("\n")
            if line.startswith("FILE: "):
                flush()
                current_file = line[6:].strip()
                continue
            # Only use polished books with explicit model answers. Book 7
            # contains generic short-answer prompts, and Extra files are notes.
            approved = re.match(r"Book_[1-6]_", current_file) is not None
            match = re.match(r"^Q\d+\.\s+(.+\?)\s*$", line) if approved else None
            interview = re.match(r"^Interview Question:\s*(.+\?)\s*$", line) if approved else None
            if match or interview:
                flush()
                question = (match or interview).group(1)
                continue
            if not question:
                continue
            if line.startswith("Model Answer:"):
                answer_lines = [line.split(":", 1)[1].strip()]
                flush()
            elif line.strip() == "Model Answer (English)":
                collecting = True
            elif collecting:
                if not line.strip() or re.match(r"^(Dịch|Vietnamese|Vocabulary|Follow-up|Assessor|Common|IPA)", line):
                    flush()
                else:
                    answer_lines.append(line.strip())
    flush()
    return records


def normalise_question(question):
    return " ".join(re.findall(r"[a-z0-9]+", question.lower()))


def walk_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_objects(child)


def parse_json_sources(data_dir):
    """Build one global id-based Q&A index from every JSON data layer."""
    questions = {}
    answers = {}

    def add_question(item_id, question):
        if item_id and isinstance(question, str) and question.strip():
            questions.setdefault(str(item_id), set()).add(" ".join(question.split()))

    def add_answer(item_id, answer, priority, source):
        if not item_id or not isinstance(answer, str):
            return
        answer = " ".join(answer.split())
        if len(answer) < 10:
            return
        candidate = (priority, -len(answer), answer, source)
        old = answers.get(str(item_id))
        if old is None or candidate[:2] > old[:2]:
            answers[str(item_id)] = candidate

    # Filesystem traversal order is not stable between machines/builds. Keep
    # same-priority, same-length answer selection reproducible.
    for path in sorted(Path(data_dir).rglob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, TypeError):
            continue
        path_text = str(path).lower()
        if "shorten_" in path.name.lower() and path.name.lower().endswith("_output.json"):
            priority = 5
        elif "/enriched/" in path_text:
            priority = 4
        elif path.name.lower().startswith("ans_") and path.name.lower().endswith("_output.json"):
            priority = 3
        else:
            priority = 2
        for item in walk_objects(data):
            item_id = item.get("id")
            add_question(item_id, item.get("question"))
            add_answer(item_id, item.get("answer"), priority, path.name)
        # Shortened answer files use {"question-id": "concise answer"}.
        if priority == 5 and isinstance(data, dict):
            for item_id, answer in data.items():
                add_answer(item_id, answer, priority, path.name)

    records = []
    for item_id, variants in sorted(questions.items()):
        answer_info = answers.get(item_id)
        if not answer_info:
            continue
        answer, source = answer_info[2], answer_info[3]
        for question in sorted(variants):
            records.append({
                "category": "database:" + source,
                "question": question,
                "answer": answer,
            })
    return records


if __name__ == "__main__":
    records = parse(sys.argv[1])
    merged = {normalise_question(item["question"]): item for item in records}
    if len(sys.argv) > 3:
        for item in parse_handbook(sys.argv[2]):
            merged.setdefault(normalise_question(item["question"]), item)
        for item in parse_json_sources(os.path.dirname(sys.argv[1])):
            key = normalise_question(item["question"])
            old = merged.get(key)
            # Prefer purpose-built concise answers, otherwise retain the main
            # curated export and only fill gaps from the global id join.
            if "shorten_" in item["category"].lower() or old is None:
                merged[key] = item
        output_path = sys.argv[3]
    else:
        output_path = sys.argv[2]
    with open(output_path, "w", encoding="utf-8") as output:
        json.dump(list(merged.values()), output, ensure_ascii=False, separators=(",", ":"))

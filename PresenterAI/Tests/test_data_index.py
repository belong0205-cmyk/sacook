"""Offline regression checks for imported question/answer data.

Run with: python3 -m unittest discover -s PresenterAI/Tests -p 'test_data_index.py'
Set SA_COOK_DATA_DIR to test a different source data directory.
"""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "Scripts" / "build_export_index.py"
SPEC = importlib.util.spec_from_file_location("build_export_index", SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
DATA_DIR = Path(os.environ.get("SA_COOK_DATA_DIR", "/Users/trunghuy/sa-cook-study/data"))


class ExportParserTests(unittest.TestCase):
    def test_category_boundary_does_not_relabel_previous_answer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "export.txt"
            path.write_text(
                "CATEGORY: Knives\nQ: Which knife?\nA: A chef's knife.\n"
                "CATEGORY: Cleaning\nQ: What is cleaning?\nA: Removing dirt.\n",
                encoding="utf-8",
            )
            self.assertEqual(builder.parse(path), [
                {"category": "Knives", "question": "Which knife?", "answer": "A chef's knife."},
                {"category": "Cleaning", "question": "What is cleaning?", "answer": "Removing dirt."},
            ])

    def test_keeps_both_questions_and_english_answer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "export.txt"
            path.write_text(
                "Q: Which knife is most versatile?\n"
                "   What knife is best for julienne?\n"
                "   (VI: Câu hỏi dịch)\n"
                "A: A chef's knife is suitable\n"
                "   for both tasks.\n"
                "   (VI: Câu trả lời dịch)\n",
                encoding="utf-8",
            )
            self.assertEqual(builder.parse(path)[0], {
                "category": "Uncategorised",
                "question": "Which knife is most versatile? What knife is best for julienne?",
                "answer": "A chef's knife is suitable for both tasks.",
            })

    def test_concise_answer_joins_by_id_not_array_position(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "questions.json").write_text(json.dumps([
                {"id": "knife", "question": "Which knife?", "answer": "Use a chef's knife for slicing."},
                {"id": "clean", "question": "What is cleaning?", "answer": "Cleaning removes visible dirt and food."},
            ]), encoding="utf-8")
            # Intentionally reverse answer order.
            (root / "shorten_A1_output.json").write_text(json.dumps([
                {"id": "clean", "answer": "Remove dirt and food."},
                {"id": "knife", "answer": "Use a chef's knife."},
            ]), encoding="utf-8")
            pairs = {r["question"]: r["answer"] for r in builder.parse_json_sources(root)}
            self.assertEqual(pairs, {
                "Which knife?": "Use a chef's knife.",
                "What is cleaning?": "Remove dirt and food.",
            })

    def test_equal_priority_selection_is_reproducible(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Create in reverse alphabetical order; equal-length candidates.
            for filename, answer in (("z.json", "Answer two."), ("a.json", "Answer one.")):
                (root / filename).write_text(json.dumps([
                    {"id": "q1", "question": "A question?", "answer": answer},
                ]), encoding="utf-8")
            self.assertEqual(builder.parse_json_sources(root)[0]["answer"], "Answer one.")


@unittest.skipUnless((DATA_DIR / "export_qa.txt").is_file(), "SA Cook source dataset is unavailable")
class SourceDatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.objects = []
        for path in sorted(DATA_DIR.rglob("*.json")):
            cls.objects.extend(builder.walk_objects(json.loads(path.read_text(encoding="utf-8"))))
        cls.records = builder.parse_json_sources(DATA_DIR)

    def test_no_global_id_collisions_in_source(self):
        questions = {}
        for item in self.objects:
            if item.get("id") and isinstance(item.get("question"), str):
                questions.setdefault(str(item["id"]), set()).add(builder.normalise_question(item["question"]))
        collisions = {key: sorted(values) for key, values in questions.items() if len(values) > 1}
        self.assertEqual(collisions, {}, "An ID now refers to different questions; global joining is unsafe")
        self.assertGreaterEqual(len(questions), 900)

    def test_export_categories_match_a_source_occurrence(self):
        expected = {}
        category = "Uncategorised"
        for line in (DATA_DIR / "export_qa.txt").read_text(encoding="utf-8").splitlines():
            if line.startswith("CATEGORY: "):
                category = line[len("CATEGORY: "):].strip()
            elif line.startswith("Q: "):
                expected.setdefault(line[3:].strip(), set()).add(category)
        for item in builder.parse(DATA_DIR / "export_qa.txt"):
            if item["question"] in expected:
                self.assertIn(item["category"], expected[item["question"]], item["question"])

    def test_all_index_answers_have_matching_source_ids(self):
        questions = {}
        answers = {}
        for item in self.objects:
            item_id = str(item.get("id", ""))
            if item_id and isinstance(item.get("question"), str):
                questions.setdefault(" ".join(item["question"].split()), set()).add(item_id)
            if item_id and isinstance(item.get("answer"), str):
                answers.setdefault(item_id, set()).add(" ".join(item["answer"].split()))
        for path in DATA_DIR.rglob("shorten_*_output.json"):
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                for item_id, answer in data.items():
                    if isinstance(answer, str):
                        answers.setdefault(item_id, set()).add(" ".join(answer.split()))
        self.assertGreaterEqual(len(self.records), 900)
        for record in self.records:
            valid_answers = set().union(*(answers.get(item_id, set()) for item_id in questions[record["question"]]))
            self.assertIn(record["answer"], valid_answers, record["question"])

    def test_reported_questions_have_relevant_data(self):
        pairs = {item["question"]: item["answer"].lower() for item in self.records}
        self.assertIn("nationality", pairs["List three ways people may define their cultural identity."])
        cleaning = pairs["What is the difference between cleaning and sanitising?"]
        self.assertIn("cleaning", cleaning)
        self.assertIn("sanitising", cleaning)
        knife = pairs["Which knife is the most versatile for slicing, chopping and dicing? What knife is best for cutting julienne or vegetables?"]
        self.assertIn("chef", knife)
        self.assertNotIn("steak", knife)


if __name__ == "__main__":
    unittest.main()

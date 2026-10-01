"""Survey selection preserves observations and rejects partial source evidence."""
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("select_surveys", Path(__file__).with_name("select-surveys.py"))
SELECT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SELECT)


class SurveySelectionTests(unittest.TestCase):
    def setUp(self):
        self.files = [dict(id=name, corpus=name, bytes=100) for name in SELECT.CACHE.SURVEY_CORPORA]
        self.files.append(dict(id="excluded-input", corpus="unrelated-project", bytes=700))
        self.rows = [dict(id=f["id"], corpus=f["corpus"], output=output, status="ok",
            wall_seconds=1.0, read_cpu_seconds=2.0, process_cpu_seconds=3.0, peak_rss_bytes=400)
            for f in self.files for output in SELECT.CACHE.OUTPUTS]

    def test_selects_only_surveys_without_changing_records_or_source(self):
        original = copy.deepcopy(self.rows)
        files, kept, excluded = SELECT.select(self.files, self.rows, 5)
        self.assertEqual({f["corpus"] for f in files}, set(SELECT.CACHE.SURVEY_CORPORA))
        self.assertEqual(kept, self.rows[:-2])
        self.assertEqual(excluded, self.rows[-2:])
        self.assertEqual(self.rows, original)
        totals = [r for r in SELECT.summaries(files, kept) if r["corpus"] == "ALL"]
        self.assertEqual(len(totals), 2)
        self.assertTrue(all(r["wall_seconds"] == 5 and r["dta_bytes"] == 500 for r in totals))

    def test_missing_duplicate_or_partial_matrix_is_rejected(self):
        for rows in (self.rows[:-1], self.rows+self.rows[:1], self.rows[:-1]+self.rows[:1]):
            with self.subTest(rows=len(rows)), self.assertRaises(RuntimeError):
                SELECT.select(self.files, rows, 5)
        with self.assertRaises(RuntimeError):
            SELECT.select(self.files, self.rows, 6)

    def test_missing_survey_is_rejected_even_if_requested_count_matches(self):
        files = self.files[1:]
        rows = [r for r in self.rows if r["id"] != self.files[0]["id"]]
        with self.assertRaisesRegex(RuntimeError, "All five survey roots"):
            SELECT.select(files, rows, 4)


if __name__ == "__main__":
    unittest.main()

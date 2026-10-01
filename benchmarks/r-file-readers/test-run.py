"""Checks for measurement rejection and unresolved-clock reporting."""
import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("reader_run", Path(__file__).with_name("run.py"))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


class MeasurementTests(unittest.TestCase):
    def test_rejects_invalid_clocks_and_shapes(self):
        fixture = {"rows": 200000, "columns": 32}
        valid = ["MEASURE", "0.5", "0.2", "0.1", "0.2", "0.1", "0.0", "0.7", "0.3", "0.1", "200000", "32"]
        self.assertAlmostEqual(RUN.validate_record(valid, fixture)["total_cpu"], 0.4)
        for index, bad_value in ((1, "nan"), (1, "inf"), (2, "-0.1"), (10, "199999"), (11, "31")):
            corrupt = valid.copy()
            corrupt[index] = bad_value
            with self.subTest(index=index, bad_value=bad_value), self.assertRaises(RuntimeError):
                RUN.validate_record(corrupt, fixture)
        with self.assertRaises(RuntimeError):
            RUN.validate_record(valid[:-1], fixture)

    def test_keeps_zero_resolution_pairs_without_ratio(self):
        rows = []
        for pair in (1, 2):
            for variant in ("baseline", "candidate"):
                metrics = dict.fromkeys(RUN.METRICS, 1.0)
                if pair == 2 and variant == "baseline":
                    metrics["read_cpu"] = 0.0
                rows.append(dict(case="example", pair=pair, variant=variant, **metrics))
        with tempfile.TemporaryDirectory() as directory:
            RUN.write_summaries(Path(directory), rows, 2)
            with open(Path(directory) / "paired-summary.csv") as stream:
                result = {row["metric"]: row for row in csv.DictReader(stream)}
            self.assertEqual(result["read_cpu"]["resolved_pairs"], "1")
            self.assertEqual(result["read_cpu"]["paired_ratio"], "")
            self.assertEqual(result["read_cpu"]["baseline_median"], "0.5")
            self.assertEqual(result["read_wall"]["paired_ratio"], "1.0")


if __name__ == "__main__":
    unittest.main()

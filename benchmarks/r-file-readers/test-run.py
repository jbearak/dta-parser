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


class QualificationTests(unittest.TestCase):
    def test_only_signature_read_only_omits_consumption(self):
        for kind in ("values", "signature"):
            for modes in (["read"], ["consume"], ["read", "consume"]):
                plan = RUN.qualification_plan({"qualification": kind}, modes)
                omit = kind == "signature" and modes == ["read"]
                with self.subTest(kind=kind, modes=modes):
                    self.assertEqual(plan["consumption"], "omitted_read_only" if omit else "complete")
                    self.assertEqual(plan["worker_mode"], "qualify-" + kind + ("-read" if omit else ""))
        self.assertEqual(RUN.qualification_plan({}, ["read"])["consumption"], "omitted_read_only")

    def test_consumption_records_cannot_claim_unperformed_work(self):
        read_plan = RUN.qualification_plan({}, ["read"])
        full_plan = RUN.qualification_plan({}, ["read", "consume"])
        read_fields = ["QUALIFIED", "signature", "omitted_read_only", "-"]
        full_fields = ["QUALIFIED", "signature", "complete", "a" * 64]
        self.assertIsNone(RUN.validate_qualification(read_fields, read_plan)["consumption_sha256"])
        self.assertEqual(RUN.validate_qualification(full_fields, full_plan)["consumption_sha256"], "a" * 64)
        for fields, plan in (
                (read_fields, full_plan), (full_fields, read_plan),
                (read_fields[:-1] + ["a" * 64], read_plan),
                (full_fields[:-1] + ["-"], full_plan),
                (full_fields[:-1] + ["invalid"], full_plan),
                (full_fields[:-1], full_plan)):
            with self.subTest(fields=fields, plan=plan), self.assertRaises(RuntimeError):
                RUN.validate_qualification(fields, plan)

    def test_absent_consumption_does_not_replace_or_compare_real_hash(self):
        signatures, consumed = {}, {}
        record = dict(signature="signature", consumption_sha256=None)
        RUN.check_qualification(record, "fixture", "first", signatures, consumed, True)
        self.assertEqual(consumed, {})
        record["consumption_sha256"] = "a" * 64
        RUN.check_qualification(record, "fixture", "second", signatures, consumed, True)
        record["consumption_sha256"] = None
        RUN.check_qualification(record, "fixture", "third", signatures, consumed, True)
        self.assertEqual(consumed, {"fixture": "a" * 64})
        record["consumption_sha256"] = "b" * 64
        with self.assertRaisesRegex(RuntimeError, "Full-consumption results differ"):
            RUN.check_qualification(record, "fixture", "changed-consumption", signatures, consumed, True)
        record.update(signature="changed", consumption_sha256=None)
        with self.assertRaisesRegex(RuntimeError, "Complete dataset signatures differ"):
            RUN.check_qualification(record, "fixture", "changed-signature", signatures, consumed, True)


if __name__ == "__main__":
    unittest.main()

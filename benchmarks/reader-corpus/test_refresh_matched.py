import csv
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("refresh_matched", Path(__file__).with_name("refresh-matched.py"))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


class RefreshMatchedTest(unittest.TestCase):
    def qualification(self):
        return dict(id="DHS-0001", containers={output: dict(rows=3, columns=2,
            signature="complete-" + output, warnings=[]) for output in ("tibble", "dibble")})

    def observations(self):
        inputs = [dict(id=corpus + "-0001", corpus=corpus, bytes="100") for corpus in RUN.EXPECTED]
        observations = [dict(id=row["id"], corpus=row["corpus"], method=method, method_position=position,
            status="ok", elapsed_seconds=0.5, read_cpu_seconds=1.5, process_cpu_seconds=2, peak_rss_bytes=1024)
            for index, row in enumerate(inputs) for position, method in enumerate(RUN.method_order(index), 1)]
        return inputs, observations

    def test_full_schedule_balances_each_method_pair(self):
        orders = [RUN.method_order(i) for i in range(1812)]
        self.assertEqual(sum(map(len, orders)), 7248)
        for method in RUN.METHODS:
            for other in RUN.METHODS:
                if method != other:
                    self.assertEqual(sum(order.index(method) < order.index(other) for order in orders), 906)
            counts = [sum(order[position] == method for order in orders) for position in range(4)]
            self.assertLessEqual(max(counts) - min(counts), 2)

    def test_qualification_permits_expected_cross_container_signature_difference(self):
        RUN.validate_qualification(self.qualification(), "DHS-0001")

    def test_qualification_rejects_incomplete_and_warning_results(self):
        for field, value in (("signature", ""), ("warnings", ["unexpected"]),
                             ("rows", 4), ("columns", 0)):
            record = self.qualification()
            record["containers"]["tibble"][field] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_qualification(record, "DHS-0001")
        record = self.qualification()
        del record["containers"]["dibble"]
        with self.assertRaises(RuntimeError):
            RUN.validate_qualification(record, "DHS-0001")
        with self.assertRaises(RuntimeError):
            RUN.validate_qualification(self.qualification(), "DHS-0002")

    def test_aggregate_requires_all_attempts_in_order(self):
        inputs, observations = self.observations()
        rows = RUN.aggregate(inputs, observations, "2026-10-01")
        self.assertEqual(len(rows), 12)
        self.assertTrue(all(r["files"] == 1 and r["wall_seconds"] == 0.5 and
                            r["read_cpu_seconds"] == 1.5 and r["process_cpu_seconds"] == 2 for r in rows))
        for invalid in (observations[:-1], observations + observations[:1], list(reversed(observations))):
            with self.assertRaises(RuntimeError):
                RUN.aggregate(inputs, invalid, "2026-10-01")

    def test_aggregate_rejects_failed_read(self):
        inputs, observations = self.observations()
        observations[0]["status"] = "error"
        with self.assertRaises(RuntimeError):
            RUN.aggregate(inputs, observations, "2026-10-01")

    def test_historical_comparator_cells_remain_exact(self):
        raw = (RUN.HISTORICAL / "corpus-summary.csv").read_bytes()
        expected = [r for r in csv.DictReader(io.StringIO(raw.decode())) if r["method"] in ("haven", "stata")]
        self.assertEqual(RUN.historical_comparators(raw), expected)
        self.assertEqual(len(expected), 6)
        self.assertTrue(all(r["measurement_date"] == "2026-08-24" for r in expected))

    def test_historical_comparator_coverage_and_date_are_required(self):
        raw = (RUN.HISTORICAL / "corpus-summary.csv").read_bytes()
        for invalid in (raw.replace(b"DHS,haven,641,", b"DHS,haven,642,"),
                        raw.replace(b"2026-08-24", b"2026-10-01"),
                        raw.replace(b"NSFG,stata,", b"NSFG,haven,")):
            with self.assertRaises(RuntimeError):
                RUN.historical_comparators(invalid)

    def test_membership_cannot_be_substituted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "membership.json"
            path.write_text("[]\n")
            with self.assertRaises(RuntimeError):
                RUN.select_membership(path, root, False)


if __name__ == "__main__":
    unittest.main()

import copy
import importlib.util
import math
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("refresh_india", Path(__file__).with_name("refresh-india.py"))
REFRESH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REFRESH)


class RefreshIndiaTest(unittest.TestCase):
    def qualification(self):
        return {method: dict(rows=3, columns=2, output=method.rsplit("_", 1)[1],
                            signature="complete-" + method.rsplit("_", 1)[1], warnings=[])
                for method in REFRESH.METHODS}

    def observation(self, output="tibble"):
        return dict(rows=3, columns=2, output=output, elapsed_seconds=0.5,
                    read_cpu_seconds=1.5, process_cpu_seconds=2, peak_rss_bytes=1024)

    def test_full_schedule_balances_methods_and_pair_order(self):
        schedule = REFRESH.round_orders()
        self.assertEqual(len(schedule), 10)
        self.assertEqual(sum(map(len, schedule)), 40)
        for method in REFRESH.METHODS:
            self.assertEqual(sorted(sum(row[position] == method for row in schedule)
                                    for position in range(4)), [2, 2, 3, 3])
            for other in REFRESH.METHODS:
                if method != other:
                    self.assertEqual(sum(row.index(method) < row.index(other) for row in schedule), 5)

    def test_full_run_requires_exact_historical_inputs_and_dimensions(self):
        REFRESH.validate_inputs(REFRESH.EXPECTED_INPUTS, 724115, 5972, False)
        for kind in ("dta", "arrow"):
            for field, value in (("bytes", 1), ("sha256", "0" * 64)):
                inputs = copy.deepcopy(REFRESH.EXPECTED_INPUTS)
                inputs[kind][field] = value
                with self.assertRaises(ValueError):
                    REFRESH.validate_inputs(inputs, 724115, 5972, False)
        with self.assertRaises(ValueError):
            REFRESH.validate_inputs(REFRESH.EXPECTED_INPUTS, 3, 2, False)
        REFRESH.validate_inputs({}, 3, 2, True)
        with self.assertRaises(ValueError):
            REFRESH.validate_inputs({}, 0, 2, True)

    def test_qualification_allows_container_storage_differences(self):
        REFRESH.validate_qualification(self.qualification(), 3, 2)

    def test_qualification_rejects_within_container_changes_and_partial_evidence(self):
        for method in REFRESH.METHODS:
            for field, value in (("signature", "different"), ("warnings", ["unexpected"]),
                                 ("rows", 4), ("columns", 3), ("output", "data.table")):
                records = self.qualification()
                records[method][field] = value
                with self.assertRaises(ValueError):
                    REFRESH.validate_qualification(records, 3, 2)
            records = self.qualification()
            del records[method]
            with self.assertRaises(ValueError):
                REFRESH.validate_qualification(records, 3, 2)

    def test_observations_reject_invalid_clocks_and_wrong_results(self):
        REFRESH.validate_observation(self.observation(), 3, 2, "tibble", False)
        for name in ("elapsed_seconds", "read_cpu_seconds", "process_cpu_seconds", "peak_rss_bytes"):
            for value in (-1, math.nan, math.inf, None, True):
                record = self.observation()
                record[name] = value
                with self.assertRaises(ValueError):
                    REFRESH.validate_observation(record, 3, 2, "tibble", False)
        for name in ("elapsed_seconds", "process_cpu_seconds", "peak_rss_bytes"):
            record = self.observation()
            record[name] = 0
            with self.assertRaises(ValueError):
                REFRESH.validate_observation(record, 3, 2, "tibble", False)
        record = self.observation()
        record["elapsed_seconds"] = 0
        REFRESH.validate_observation(record, 3, 2, "tibble", True)
        with self.assertRaises(ValueError):
            REFRESH.validate_observation(self.observation("dibble"), 3, 2, "tibble", False)

    def test_summary_requires_every_attempt_in_actual_order(self):
        schedule = REFRESH.round_orders()
        rows = [dict(iteration=iteration, position=position, method=method,
                     **self.observation(method.rsplit("_", 1)[1]))
                for iteration, order in enumerate(schedule, 1)
                for position, method in enumerate(order, 1)]
        summary = REFRESH.summarize(rows, schedule)
        self.assertEqual(len(summary), 4)
        for row in summary:
            self.assertEqual(row["observations"], 10)
            self.assertEqual(row["median_seconds"], 0.5)
            self.assertEqual(row["median_read_cpu_seconds"], 1.5)
            self.assertEqual(row["median_process_cpu_seconds"], 2)
        for invalid in (rows[:-1], rows + rows[:1], list(reversed(rows))):
            with self.assertRaises(ValueError):
                REFRESH.summarize(invalid, schedule)

    def test_historical_comparator_cells_are_preserved(self):
        raw = (REFRESH.HISTORICAL / "summary.csv").read_bytes()
        rows = REFRESH.historical_comparators(raw)
        self.assertEqual([row["method"] for row in rows], ["haven", "stata"])
        self.assertEqual([row["median_seconds"] for row in rows], ["472.99649999999997", "0.4725"])
        self.assertEqual([row["median_process_cpu_seconds"] for row in rows],
                         ["473.047814", "0.5070254999999999"])
        self.assertEqual({row["measurement_date"] for row in rows}, {"2026-09-16"})
        with self.assertRaises(ValueError):
            REFRESH.historical_comparators(raw.replace(b"haven,10,", b"haven,9,"))
        with self.assertRaises(ValueError):
            REFRESH.historical_comparators(raw.replace(b"stata,10,", b"haven,10,"))

    def test_public_record_rejects_private_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "public.json"
            with self.assertRaises(ValueError):
                REFRESH.write_public(path, {"path": "/private/tmp/input.dta"})
            self.assertFalse(path.exists())
            REFRESH.write_public(path, {"sha256": "a" * 64})
            self.assertTrue(path.is_file())


if __name__ == "__main__":
    unittest.main()

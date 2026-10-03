#!/usr/bin/env python3
"""Reject incomplete or contradictory actual-header diagnostic records."""
import copy
import csv
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('work_count', HERE / 'work-count.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class Records(unittest.TestCase):
    def setUp(self):
        with (HERE / 'fixtures/work-count-red.csv').open(newline='') as stream:
            self.rows = list(csv.DictReader(stream))

    def test_recorded_red_matrix(self):
        self.assertEqual(probe.validate_rows(self.rows), (0, 58))

    def test_missing_case(self):
        with self.assertRaises(RuntimeError):
            probe.validate_rows(self.rows[:-1])

    def test_duplicate_case(self):
        self.rows[-1] = copy.deepcopy(self.rows[0])
        with self.assertRaises(RuntimeError):
            probe.validate_rows(self.rows)

    def test_changed_order(self):
        self.rows[0], self.rows[1] = self.rows[1], self.rows[0]
        with self.assertRaises(RuntimeError):
            probe.validate_rows(self.rows)

    def test_fractional_counter(self):
        self.rows[0]['proof_rows'] = '1.5'
        with self.assertRaises(RuntimeError):
            probe.validate_rows(self.rows)

    def test_suppressed_all_missing_work(self):
        row = next(r for r in self.rows if r['all_missing_work_failure'] == '1')
        row['all_missing_work_failure'] = '0'
        with self.assertRaises(RuntimeError):
            probe.validate_rows(self.rows)

    def test_incomplete_all_missing_result(self):
        row = next(r for r in self.rows if r['all_missing_gate'] == '1')
        row['result_missing'] = row['stored_missing'] = '0'
        with self.assertRaises(RuntimeError):
            probe.validate_rows(self.rows)

    def test_semantic_failure_is_separate_from_work(self):
        self.rows[0]['semantic_error'] = '3'
        self.assertEqual(probe.validate_rows(self.rows), (1, 58))

if __name__ == '__main__':
    unittest.main()

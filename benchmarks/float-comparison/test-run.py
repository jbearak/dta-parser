#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('comparison_run', Path(__file__).with_name('run.py'))
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)


def observations():
    rows = []
    for variant in ('baseline', 'candidate'):
        for number in range(1, 7):
            for threads, missing, operation, representation in sorted(run.CASES):
                compact = str(representation == 'compact').upper()
                rows.append(dict(variant=variant, round=str(number), threads=threads,
                    missing=missing, operation=operation, representation=representation,
                    position=str((number + run.REPRESENTATIONS.index(representation)) % 3 + 1),
                    rows='1000000', repetitions='10', cpu='.3', wall='.3',
                    result_hash='a' * 64, input_hash='b' * 64, y_hash='c' * 64,
                    metadata_x='d' * 64, metadata_y='e' * 64,
                    compact_before=compact, compact_after=compact,
                    y_compact_before=compact, y_compact_after=compact,
                    materialized_before='FALSE', materialized_after='FALSE',
                    y_materialized_before='FALSE', y_materialized_after='FALSE',
                    native_qualified=str(representation != 'ordinary').upper()))
    return rows


class Protocol(unittest.TestCase):
    def setUp(self):
        self.rows = observations()

    def test_complete(self):
        run.validate_all(self.rows, 6)
        self.assertEqual(len(run.summarize(self.rows)), 12)

    def test_missing_or_duplicate(self):
        for bad in (self.rows[:-1], self.rows + [self.rows[0]]):
            with self.assertRaises(RuntimeError):
                run.validate_all(bad, 6)

    def test_nonpositive_or_nonfinite_timing(self):
        for value in ('0', '-1', 'nan', 'inf'):
            bad = copy.deepcopy(self.rows)
            bad[0]['cpu'] = value
            with self.assertRaises(RuntimeError):
                run.validate_all(bad, 6)

    def test_native_not_qualified(self):
        self.rows[0]['native_qualified'] = 'FALSE'
        with self.assertRaises(RuntimeError):
            run.validate_all(self.rows, 6)

    def test_source_changed(self):
        for field, value in (('compact_after', 'FALSE'), ('metadata_x', 'f' * 64), ('input_hash', 'f' * 64)):
            bad = copy.deepcopy(self.rows)
            bad[0][field] = value
            with self.assertRaises(RuntimeError):
                run.validate_all(bad, 6)

    def test_unbalanced_order(self):
        for row in self.rows:
            row['position'] = '1'
        with self.assertRaises(RuntimeError):
            run.validate_all(self.rows, 6)

    def test_result_difference(self):
        self.rows[0]['result_hash'] = 'f' * 64
        with self.assertRaises(RuntimeError):
            run.validate_all(self.rows, 6)

    def test_bare_missing_contract_may_differ(self):
        for row in self.rows:
            if row['representation'] == 'ordinary' and row['missing'] == 'TRUE':
                row['result_hash'] = 'f' * 64
        run.validate_all(self.rows, 6)


if __name__ == '__main__':
    unittest.main()

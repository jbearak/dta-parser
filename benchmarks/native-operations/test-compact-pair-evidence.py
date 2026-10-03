#!/usr/bin/env python3
"""Corrupt suite flags/counts must fail even when Python assertions are disabled."""
import copy
import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('pair_evidence', HERE / 'verify-compact-pair-evidence.py')
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class EvidenceTests(unittest.TestCase):
    def parse(self, **changes):
        row = dict(file='test-example.R', test='complete operation', passed='3', failed='0',
                   error='FALSE', skipped='FALSE', warning='0')
        row.update(changes)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'suite.csv'
            with path.open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=VERIFY.FIELDS)
                writer.writeheader()
                writer.writerow(row)
            return VERIFY.suite_totals(path, {'blocks': 1, 'totals': dict(
                passed=3, failed=0, error=0, skipped=0, warning=0)})

    def test_exact_statuses_pass(self):
        self.assertEqual(self.parse()['totals']['passed'], 3)

    def test_malformed_or_missing_status_fails(self):
        for field in ('error', 'skipped'):
            for value in ('true', 'false', '1', '0', '', None, ' TRUE'):
                with self.subTest(field=field, value=value), self.assertRaisesRegex(
                        RuntimeError, 'Malformed suite status'):
                    self.parse(**{field: value})

    def test_failed_or_skipped_suite_fails(self):
        for field, value in [('error', 'TRUE'), ('skipped', 'TRUE'), ('failed', '1')]:
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, 'Suite failed'):
                self.parse(**{field: value})

    def test_noninteger_or_negative_count_fails(self):
        for field in ('passed', 'failed', 'warning'):
            for value in ('-1', '1.0', 'NaN', '', None):
                with self.subTest(field=field, value=value), self.assertRaisesRegex(
                        RuntimeError, 'Malformed suite count'):
                    self.parse(**{field: value})

    def test_changed_binding_total_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'Suite differs'):
            self.parse(passed='4')

    def test_receipt_and_observed_source_must_match(self):
        inventory = {'source': {'src/example.c': 'a' * 64},
                     'receipt': {'source_inventory': {'src/example.c': 'a' * 64}}}
        self.assertEqual(VERIFY.receipt_source(inventory), inventory['source'])
        changed = copy.deepcopy(inventory)
        changed['receipt']['source_inventory']['src/example.c'] = 'b' * 64
        with self.assertRaisesRegex(RuntimeError, 'Receipt/source inventory mismatch'):
            VERIFY.receipt_source(changed)

    def test_identity_values_and_low_entropy_digests_are_private(self):
        for name in ('USER', 'LOGNAME'):
            valid = {'nested': [{name: {'value': '<private>', 'sha256': '<private>'}}]}
            VERIFY.check_identity_metadata(valid)
            for field in ('value', 'sha256'):
                changed = copy.deepcopy(valid)
                changed['nested'][0][name][field] = '1' * 64
                with self.assertRaisesRegex(RuntimeError, 'Identity environment'):
                    VERIFY.check_identity_metadata(changed)


if __name__ == '__main__':
    unittest.main()

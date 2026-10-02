#!/usr/bin/env python3
"""Controller checks only; never builds a package or runs an R benchmark."""
from contextlib import redirect_stdout
import copy
import csv
import importlib.util
import io
import itertools
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('native_operations_run', HERE / 'run.py')
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def expected_cases(arithmetic_only=False):
    arithmetic = ('multiply', 'divide', 'add')
    result = set(itertools.product(
        ('dta', 'arrow'), ('byte', 'int', 'long', 'float'), arithmetic,
        ('compact', 'ordinary', 'typed_double')))
    if not arithmetic_only:
        result.update(itertools.product(
            ('dta', 'arrow'), ('byte', 'int', 'long', 'float'),
            ('is_tagged_missing', 'missing_tag', 'anyNA', 'dta_total',
             'dta_row_total', 'mean', 'range', 'summ', 'dta_match', 'dta_in'),
            ('compact', 'ordinary')))
        result.update(itertools.product(
            ('constructed', 'retained'), ('byte', 'int', 'long', 'float'),
            ('anyNA_late',), ('compact', 'ordinary')))
    return result


def observations(arithmetic_only=False, round_number=1):
    result = []
    for case in sorted(expected_cases(arithmetic_only)):
        row = dict(zip(('format', 'width', 'operation', 'representation'), case))
        row.update(round=str(round_number), iterations='100', rows='1000000',
                   cpu_seconds='0.15', elapsed_seconds='0.15',
                   native_scalar_calls='100', result_storage=case[1],
                   result_sha256='canonical-' + '/'.join(case),
                   full_result_sha256='complete-' + '/'.join(case))
        result.append(row)
    return result


class MatrixTests(unittest.TestCase):
    def test_default_is_the_complete_248_case_matrix(self):
        expected = expected_cases()
        self.assertEqual(len(expected), 248)
        self.assertEqual(RUN.EXPECTED_CASES, expected)
        RUN.validate_round(observations(round_number=6), 6)

    def test_arithmetic_is_the_complete_72_case_matrix(self):
        expected = expected_cases(True)
        self.assertEqual(len(expected), 72)
        RUN.validate_round(observations(True, 6), 6, expected)
        with self.assertRaisesRegex(RuntimeError, 'complete unique case matrix'):
            RUN.validate_round(observations(True), 1)

    def test_incomplete_duplicate_and_wrong_round_results_are_refused(self):
        for arithmetic_only in (False, True):
            expected = expected_cases(arithmetic_only)
            rows = observations(arithmetic_only)
            malformed = {
                'missing': rows[:-1],
                'duplicate': rows + [rows[0]],
                'duplicate replacing missing': rows[:-1] + [rows[0]],
                'wrong round': [dict(row, round='2') for row in rows],
                'zero repetitions': [dict(row, iterations='0') for row in rows],
                'wrong input size': [dict(row, rows='999999') for row in rows],
            }
            for reason, bad in malformed.items():
                with self.subTest(arithmetic_only=arithmetic_only, reason=reason):
                    with self.assertRaises(RuntimeError):
                        RUN.validate_round(bad, 1, expected)


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.fixtures = self.root / 'fixtures'
        self.fixtures.mkdir()
        for extension in ('dta', 'arrow', 'rds'):
            (self.fixtures / ('compact.' + extension)).write_bytes(extension.encode())
        self.inventory_calls = []
        self.worker_calls = []

    def receipt(self, build, variant):
        self.inventory_calls.append((build, variant))
        return copy.deepcopy({
            'source': {}, 'installed': {'libs/dtatools.so': 'verified-dll'},
            'receipt': {'base_commit': variant + '-commit'},
            'receipt_sha256': variant + '-receipt',
        })

    def execute(self, arithmetic_only=False, receipt=None):
        output = self.root / ('arithmetic' if arithmetic_only else 'full')
        argv = [str(HERE / 'run.py'), '--baseline', str(self.root / 'baseline'),
                '--candidate', str(self.root / 'candidate'),
                '--fixtures', str(self.fixtures), '--output', str(output)]
        if arithmetic_only:
            argv.append('--arithmetic-only')

        def worker(command, **kwargs):
            self.worker_calls.append(command)
            self.assertEqual(command[7:], ['arithmetic'] if arithmetic_only else [])
            rows = observations(arithmetic_only, int(command[5]))
            with Path(command[6]).open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)

        # Mock external processes, their platform description and the receipt
        # reader. Matrix checks, hashes, provenance comparison and completion run.
        with mock.patch.object(RUN.sys, 'argv', argv), \
             mock.patch.object(RUN, 'inventory', side_effect=receipt or self.receipt), \
             mock.patch.object(RUN.platform, 'platform', return_value='test-platform'), \
             mock.patch.object(RUN.subprocess, 'check_output', return_value='R test\n'), \
             mock.patch.object(RUN.subprocess, 'run', side_effect=worker), \
             redirect_stdout(io.StringIO()):
            RUN.main()
        return output

    def test_both_modes_validate_all_rounds_and_keep_provenance(self):
        for arithmetic_only, count in ((False, 248), (True, 72)):
            with self.subTest(arithmetic_only=arithmetic_only):
                self.inventory_calls.clear()
                self.worker_calls.clear()
                output = self.execute(arithmetic_only)
                self.assertEqual(len(self.worker_calls), 12)
                self.assertEqual([variant for _, variant in self.inventory_calls],
                                 ['baseline', 'candidate', 'baseline', 'candidate'])
                completion = json.loads((output / 'completion.json').read_text())
                self.assertEqual(completion['observations'], 12 * count)
                self.assertTrue(completion['exact_results'])
                self.assertTrue(completion['provenance_unchanged'])
                self.assertEqual(completion['source_patch_sha256'],
                                 RUN.digest(output / 'source.patch'))
                before = json.loads((output / 'provenance-before.json').read_text())
                after = json.loads((output / 'provenance-after.json').read_text())
                for key in ('builds', 'fixtures', 'controllers'):
                    self.assertEqual(before[key], after[key])

    def test_receipt_failure_prevents_worker_execution(self):
        def invalid_receipt(build, variant):
            raise RuntimeError('clean-build receipt rejected')

        with self.assertRaisesRegex(RuntimeError, 'clean-build receipt rejected'):
            self.execute(True, invalid_receipt)
        self.assertEqual(self.worker_calls, [])
        self.assertFalse((self.root / 'arithmetic' / 'completion.json').exists())

    def test_changed_build_receipt_prevents_completion(self):
        def changed_receipt(build, variant):
            record = self.receipt(build, variant)
            if len(self.inventory_calls) > 2:
                record['installed']['libs/dtatools.so'] = 'changed-dll'
            return record

        with self.assertRaisesRegex(RuntimeError, 'build or fixture changed'):
            self.execute(True, changed_receipt)
        self.assertEqual(len(self.worker_calls), 12)
        self.assertFalse((self.root / 'arithmetic' / 'completion.json').exists())


if __name__ == '__main__':
    unittest.main()

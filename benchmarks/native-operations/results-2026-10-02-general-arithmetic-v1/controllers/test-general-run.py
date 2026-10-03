#!/usr/bin/env python3
"""Malformed arithmetic evidence must fail before a completion record is written."""
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
SPEC = importlib.util.spec_from_file_location('general_run', HERE / 'general-run.py')
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def cases():
    result = set(itertools.product(('int', 'float'), ('FALSE', 'TRUE'),
        ('scale_binary', 'scale_general', 'pair_compact_double', 'add_scalar',
         'subtract_scalar', 'reverse_subtract', 'reverse_divide'),
        ('compact', 'typed_double', 'ordinary')))
    for width, operation in [('int', 'mixed_add'), ('int', 'mixed_multiply'), ('long', 'long_float_add')]:
        result.update((width, missing, operation, rep) for missing in ('FALSE', 'TRUE')
                      for rep in ('compact', 'typed_double', 'ordinary'))
    return result


def observations(round_number=1):
    rows = []
    for case in sorted(cases()):
        row = dict(zip(('width', 'missing', 'operation', 'representation'), case))
        rep = case[-1]
        row.update(round=str(round_number), n='1000000', iterations='20', cpu='.15', wall='.16',
            native_calls='0' if rep == 'ordinary' else '20',
            order=str((('compact', 'typed_double', 'ordinary').index(rep) + round_number - 1) % 3 + 1),
            result_sha256='0'*64, missing_sha256='1'*64, input_sha256='2'*64, y_sha256='3'*64,
            missing_count='0', result_storage='' if rep == 'ordinary' else 'double')
        for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
            row[prefix + '_before'] = row[prefix + '_after'] = 'TRUE' if prefix == 'compact' and rep == 'compact' else 'FALSE'
        rows.append(row)
    return rows


class EvidenceTests(unittest.TestCase):
    def test_complete_matrix_is_102_observations(self):
        self.assertEqual(len(cases()), 102)
        self.assertEqual(cases(), RUN.EXPECTED)
        RUN.validate_round(observations(), 1, 'candidate')

    def test_missing_duplicate_invalid_time_source_and_native_route_fail(self):
        source = observations()
        malformed = [source[:-1], source + [source[0]], source[:-1] + [source[0]]]
        for key, value in [('cpu', 'nan'), ('wall', '0'), ('round', '2'), ('n', '10'),
                           ('iterations', '0'), ('result_sha256', 'no hash'),
                           ('materialized_after', 'TRUE'), ('native_calls', '0')]:
            row = copy.deepcopy(source)
            compact = next(r for r in row if r['representation'] == 'compact')
            compact[key] = value
            malformed.append(row)
        for rows in malformed:
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'candidate')

    def execute(self, corruption=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        output = root / 'output'
        calls = []
        receipts = []

        def inventory(build, variant):
            receipts.append(variant)
            result = {'source': {}, 'installed': {'dll': 'verified'}, 'receipt': {'base_commit': variant}}
            if corruption == 'receipt' and len(receipts) > 2:
                result['installed']['dll'] = 'changed'
            return result

        def worker(command, **kwargs):
            calls.append(command)
            rows = observations(int(command[4]))
            if corruption == 'result' and command[6] == 'candidate':
                rows[0]['result_sha256'] = '4'*64
            if corruption == 'unbalanced':
                rows = observations(1)
                for row in rows:
                    row['round'] = command[4]
            with Path(command[5]).open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)

        with mock.patch('sys.argv', ['general-run.py', '--baseline', str(root/'baseline'),
                    '--candidate', str(root/'candidate'), '--output', str(output)]), \
             mock.patch.object(RUN.RECORDS, 'inventory', side_effect=inventory), \
             mock.patch.object(RUN.subprocess, 'check_output', return_value='R test\n'), \
             mock.patch.object(RUN.subprocess, 'run', side_effect=worker), \
             mock.patch.object(RUN.platform, 'platform', return_value='test platform'), \
             redirect_stdout(io.StringIO()):
            if corruption:
                with self.assertRaises(RuntimeError):
                    RUN.main()
                self.assertFalse((output/'completion.json').exists())
            else:
                RUN.main()
                result = json.loads((output/'completion.json').read_text())
                self.assertEqual(result['observations'], 1224)
                self.assertTrue(result['provenance_unchanged'])
        self.assertEqual(len(calls), 12)

    def test_controller_rejects_changed_build_result_and_unbalanced_rounds(self):
        for corruption in (None, 'receipt', 'result', 'unbalanced'):
            with self.subTest(corruption=corruption):
                self.execute(corruption)


if __name__ == '__main__':
    unittest.main()

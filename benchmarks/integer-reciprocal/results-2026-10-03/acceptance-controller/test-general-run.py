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
            missing_count='0', result_storage='' if rep == 'ordinary' else 'double',
            mutation_checked='FALSE' if rep == 'ordinary' else 'TRUE',
            cleared_sha256='' if rep == 'ordinary' else '5'*64)
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
                           ('materialized_after', 'TRUE'), ('native_calls', '0'),
                           ('mutation_checked', 'FALSE'), ('cleared_sha256', 'bad')]:
            row = copy.deepcopy(source)
            compact = next(r for r in row if r['representation'] == 'compact')
            compact[key] = value
            malformed.append(row)
        for rows in malformed:
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'candidate')

    def test_baseline_native_route_is_also_required(self):
        rows = observations()
        next(row for row in rows if row['representation'] == 'compact')['native_calls'] = '0'
        with self.assertRaisesRegex(RuntimeError, 'Native arithmetic route'):
            RUN.validate_round(rows, 1, 'baseline')

    def test_missing_rscript_has_clear_error(self):
        with mock.patch('sys.argv', ['general-run.py', '--baseline', 'baseline',
                    '--candidate', 'candidate', '--output', 'output']), \
             mock.patch.object(RUN.platform, 'system', return_value='Linux'), \
             mock.patch.object(RUN.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'Rscript was not found on PATH'):
                RUN.main()

    def test_runtime_version_uses_the_exact_worker_launcher(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            launcher = root / 'worker-Rscript'
            launcher.write_bytes(b'launcher')
            runtime = root / 'R-home/bin/exec/R'
            runtime.parent.mkdir(parents=True)
            runtime.write_bytes(b'runtime')
            with mock.patch.object(RUN.subprocess, 'check_output',
                    side_effect=[str(root / 'R-home') + '\n', 'R worker version\n']) as query:
                observed = RUN.worker_runtime(launcher)
            self.assertEqual(observed['R_version'], 'R worker version')
            self.assertEqual(observed['Rscript_launcher_sha256'], RUN.sha(launcher))
            self.assertEqual(observed['R_runtime_sha256'], RUN.sha(runtime))
            self.assertEqual(query.call_args_list, [
                mock.call([str(launcher), '--vanilla', '-e', 'cat(R.home())'], text=True),
                mock.call([str(launcher), '--vanilla', '-e', 'cat(R.version.string)'], text=True)])

    def test_windows_is_rejected_before_runtime_queries(self):
        with mock.patch('sys.argv', ['general-run.py', '--baseline', 'baseline',
                    '--candidate', 'candidate', '--output', 'output']), \
             mock.patch.object(RUN.platform, 'system', return_value='Windows'), \
             mock.patch.object(RUN.subprocess, 'check_output',
                               side_effect=AssertionError('Unexpected runtime query')):
            with self.assertRaisesRegex(RuntimeError, 'Windows is not supported'):
                RUN.main()


    def execute(self, corruption=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        output = root / 'output'
        calls = []
        receipts = []
        launcher = root / 'Rscript'
        launcher.write_text('test launcher')
        for role in ('baseline', 'candidate'):
            directory = root / role
            directory.mkdir()
            (directory / 'build-receipt.json').write_text(json.dumps({'variant': 'baseline'}))
        runtimes = []

        def runtime(rscript):
            self.assertEqual(rscript, launcher.resolve())
            runtimes.append(rscript)
            changed = corruption == 'initial_runtime' or (corruption == 'runtime' and len(runtimes) > 1)
            return dict(Rscript_launcher_sha256='launcher',
                        R_runtime_sha256='changed' if changed else 'runtime',
                        R_version='changed' if corruption == 'runtime_version' and len(runtimes) > 1
                                  else 'R worker version')

        def inventory(build, variant):
            receipts.append(variant)
            result = {'source': {}, 'installed': {'dll': 'verified'}, 'receipt': {'base_commit': RUN.COMMITS[build.name], 'variant': variant, 'toolchain': {'R_runtime_sha256': 'runtime'}}}
            if corruption == 'source_commit':
                result['receipt']['base_commit'] = '0' * 40
            if corruption == 'receipt_variant':
                result['receipt']['variant'] = 'candidate'
            if corruption == 'receipt' and len(receipts) > 2:
                result['installed']['dll'] = 'changed'
            return result

        def worker(command, **kwargs):
            self.assertEqual(command[0], str(launcher.resolve()))
            calls.append(command)
            rows = observations(int(command[4]))
            if corruption == 'result' and Path(command[5]).name.endswith('-candidate.csv'):
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
             mock.patch.object(RUN.shutil, 'which', return_value=str(launcher)), \
             mock.patch.object(RUN, 'worker_runtime', side_effect=runtime), \
             mock.patch.object(RUN.subprocess, 'check_output',
                               side_effect=AssertionError('Unbound version query')), \
             mock.patch.object(RUN.subprocess, 'run', side_effect=worker), \
             mock.patch.object(RUN.platform, 'system', return_value='Linux'), \
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
        self.assertEqual(len(calls), 0 if corruption in ('initial_runtime', 'source_commit', 'receipt_variant') else 12)

    def test_controller_rejects_changed_build_result_and_unbalanced_rounds(self):
        for corruption in (None, 'receipt', 'result', 'unbalanced', 'runtime', 'runtime_version',
                           'initial_runtime', 'source_commit', 'receipt_variant'):
            with self.subTest(corruption=corruption):
                self.execute(corruption)


if __name__ == '__main__':
    unittest.main()

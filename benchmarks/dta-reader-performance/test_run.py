"""Exercise runner sequencing and failure paths without loading R or a dataset."""
import contextlib
import csv
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('reader_performance_run', Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

FAKE_WORKER = r'''
import json, os, pathlib, sys
if '--version' in sys.argv:
    print('fake Rscript for runner tests')
    raise SystemExit(0)
case = json.loads(pathlib.Path(sys.argv[3]).read_text())
qualify = os.environ['DTA_READ_PERF_SIGNATURE'] == '1'
entry = dict(case=case['name'], library=pathlib.Path(os.environ['DTATOOLS_BENCH_LIB']).name,
             qualify=qualify, reads=int(sys.argv[6]),
             flags={k: v for k, v in os.environ.items()
                    if k.startswith(('DTA_READ_PERF_', 'DTATOOLS_EXPERIMENT_'))})
with open(os.environ['FAKE_EVENT_LOG'], 'a') as stream:
    stream.write(json.dumps(entry) + '\n')
if os.environ.get('FAKE_FAIL') == '1':
    raise SystemExit(9)
rows = case['rows'] + int(not qualify and os.environ.get('FAKE_BAD_SHAPE') == '1')
for index in range(1, int(sys.argv[6]) + 1):
    print('READ\t%d\t%s\t%d\t%d' % (index, '999' if qualify else '.125', rows, case['columns']))
if qualify and os.environ.get('FAKE_NO_SIGNATURE') != '1':
    suffix = '1111111111111111' if os.environ.get('FAKE_MISMATCH') == '1' else '0000000000000000'
    print('SIGNATURE %d:%d:%s' % (case['rows'], case['columns'], suffix))
if not qualify and os.environ.get('FAKE_TIMED_SIGNATURE') == '1':
    print('SIGNATURE 3:2:0000000000000000')
if (qualify and os.environ.get('FAKE_MUTATE') == '1') or (
        not qualify and os.environ.get('FAKE_MUTATE_TIMED') == '1'):
    with open(pathlib.Path(os.environ['DTATOOLS_BENCH_LIB']) / 'dtatools' / 'DESCRIPTION', 'a') as stream:
        stream.write('changed after qualification')
'''


class RunnerTests(unittest.TestCase):
    """Check sequencing and retained failure evidence with tiny fake installations."""
    def setUp(self):
        """Create two small cases, two package directories and a fake R executable."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fake = self.root / 'Rscript'
        self.fake.write_text('#!' + sys.executable + '\n' + FAKE_WORKER)
        self.fake.chmod(0o755)
        self.events = self.root / 'events.jsonl'
        self.output = self.root / 'output'
        self.plan_path = self.root / 'plan.json'
        self.plan = dict(repetitions=2, reads_per_process=2, order='alternate', cases=[], variants=[])
        for name in ['first', 'second']:
            source = self.root / (name + '.fixture')
            case = dict(name=name, path=str(source), rows=3, columns=2)
            source.write_text(json.dumps(case))
            self.plan['cases'].append(case)
        # Qualification must still run stock first, irrespective of timing order.
        for name in ['candidate', 'stock']:
            library = self.root / name / 'dtatools'
            library.mkdir(parents=True)
            (library / 'DESCRIPTION').write_text('Package: dtatools\n')
            self.plan['variants'].append(dict(name=name, library=str(library.parent),
                env=dict(FAKE_EVENT_LOG=str(self.events))))

    def run_plan(self):
        """Run the real driver while substituting only the child executable and versions."""
        self.plan_path.write_text(json.dumps(self.plan))
        with patch.object(runner.shutil, 'which', return_value=str(self.fake)), \
                patch.object(runner, 'tool_version', return_value={'test_double': True}), \
                contextlib.redirect_stdout(io.StringIO()):
            runner.run(self.plan_path, self.output)

    def events_read(self):
        """Read the fake child execution sequence."""
        return [json.loads(line) for line in self.events.read_text().splitlines()]

    def test_every_signature_precedes_timing_and_flags_are_explicit(self):
        """Exclude qualification metrics and inherited flags from timed measurements."""
        self.plan['variants'][0]['env'].update(DTA_READ_PERF_BULK_BYTE='1',
                                              DTA_READ_PERF_SIGNATURE='1')
        with patch.dict(os.environ, DTA_READ_PERF_PROFILE='1', DTA_READ_PERF_SIGNATURE='1',
                        DTATOOLS_EXPERIMENT_AUTO_POLICY='1'):
            self.run_plan()
        events = self.events_read()
        self.assertEqual(len(events), 12)
        self.assertEqual([e['qualify'] for e in events], [True] * 4 + [False] * 8)
        self.assertEqual([e['library'] for e in events[:4]], ['stock', 'candidate'] * 2)
        for event in events:
            self.assertEqual(event['reads'], 1 if event['qualify'] else 2)
            self.assertEqual(event['flags']['DTA_READ_PERF_SIGNATURE'], '1' if event['qualify'] else '0')
            self.assertNotIn('DTA_READ_PERF_PROFILE', event['flags'])
            self.assertNotIn('DTATOOLS_EXPERIMENT_AUTO_POLICY', event['flags'])
            self.assertEqual(event['flags'].get('DTA_READ_PERF_BULK_BYTE'),
                             '1' if event['library'] == 'candidate' else None)
        with (self.output / 'observations.csv').open() as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 16)
        self.assertEqual({float(row['elapsed_seconds']) for row in rows}, {.125})
        metadata = json.loads((self.output / 'run-metadata.json').read_text())
        self.assertEqual(metadata['status'], 'complete')
        self.assertEqual(len(metadata['qualifications']), 4)
        self.assertIn('jobs.jsonl', metadata['artifacts'])
        self.assertTrue((self.output / 'baseline.md').is_file())
        self.assertEqual(json.loads((self.output / 'binding.json').read_text()),
                         json.loads((self.output / 'binding-after.json').read_text()))

    def assert_failed_before_timing(self, expected):
        """Require a recorded qualification failure and no timed processes or summary."""
        with self.assertRaisesRegex((ValueError, RuntimeError), expected):
            self.run_plan()
        self.assertTrue(all(event['qualify'] for event in self.events_read()))
        self.assertFalse((self.output / 'observations.csv').exists())
        self.assertFalse((self.output / 'summary.csv').exists())
        metadata = json.loads((self.output / 'run-metadata.json').read_text())
        self.assertEqual(metadata['status'], 'failed')
        self.assertTrue((self.output / 'jobs.jsonl').is_file())

    def test_mismatched_values_stop_before_timing(self):
        """Reject a candidate whose full data signature differs from stock."""
        self.plan['variants'][0]['env']['FAKE_MISMATCH'] = '1'
        self.assert_failed_before_timing('signature differs from stock')

    def test_missing_signature_stops_before_timing(self):
        """Reject a child that does not produce a qualification signature."""
        self.plan['variants'][0]['env']['FAKE_NO_SIGNATURE'] = '1'
        self.assert_failed_before_timing('missing or malformed signature')

    def test_changed_installation_stops_before_timing(self):
        """Reject package bytes changed by a qualification process."""
        self.plan['variants'][0]['env']['FAKE_MUTATE'] = '1'
        self.assert_failed_before_timing('changed during qualification')

    def test_failed_child_is_retained(self):
        """Keep the failing child exit code in the execution manifest."""
        self.plan['variants'][0]['env']['FAKE_FAIL'] = '1'
        self.assert_failed_before_timing('failed: qualify-first-candidate')
        jobs = [json.loads(line) for line in (self.output / 'jobs.jsonl').read_text().splitlines()]
        self.assertEqual(jobs[-1]['exit_code'], 9)

    def test_timed_dimensions_are_still_checked(self):
        """Reject a changed result shape during the measurement phase."""
        self.plan['variants'][0]['env']['FAKE_BAD_SHAPE'] = '1'
        with self.assertRaisesRegex(RuntimeError, 'invalid READ result or dimensions'):
            self.run_plan()
        self.assertEqual(len([e for e in self.events_read() if e['qualify']]), 4)
        self.assertFalse((self.output / 'summary.csv').exists())

    def test_signature_work_is_rejected_in_timed_process(self):
        """Reject signature work that could contaminate timing or peak RSS."""
        self.plan['variants'][0]['env']['FAKE_TIMED_SIGNATURE'] = '1'
        with self.assertRaisesRegex(RuntimeError, 'unexpected signature work'):
            self.run_plan()
        self.assertFalse((self.output / 'summary.csv').exists())

    def test_changed_installation_during_timing_has_no_summary(self):
        """Require the final binding check even when every child read succeeds."""
        self.plan['variants'][0]['env']['FAKE_MUTATE_TIMED'] = '1'
        with self.assertRaisesRegex(RuntimeError, 'changed during timing'):
            self.run_plan()
        self.assertEqual(len(self.events_read()), 12)
        self.assertTrue((self.output / 'binding-after.json').is_file())
        self.assertFalse((self.output / 'summary.csv').exists())
        self.assertEqual(json.loads((self.output / 'run-metadata.json').read_text())['status'],
                         'failed')

    def test_colliding_job_keys_are_rejected(self):
        """Reject names that would overwrite another case/variant log."""
        self.plan['cases'][0]['name'] = 'a-b'
        self.plan['cases'][1]['name'] = 'a'
        self.plan['variants'][0]['name'] = 'stock'
        self.plan['variants'][1]['name'] = 'b-stock'
        with self.assertRaisesRegex(ValueError, 'duplicate job keys'):
            self.run_plan()
        self.assertFalse(self.output.exists())

    def test_stock_is_required_without_creating_output(self):
        """Require an explicit stock control before starting the run."""
        self.plan['variants'].pop()
        with self.assertRaisesRegex(ValueError, 'stock variant is required'):
            self.run_plan()
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('parity_driver', Path(__file__).with_name('run.py'))
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class DriverTest(unittest.TestCase):
    @unittest.skipUnless(hasattr(os, 'wait4'), 'The measurement controller requires Unix resource accounting')
    def test_relative_cli_paths_survive_worker_directory_changes(self):
        # A stand-in executable exercises the real subprocess/job-file protocol
        # without making this path-handling test depend on R or Stata.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / 'bin'
            binary.mkdir()
            rscript = binary / 'Rscript'
            rscript.write_text(f'#!{sys.executable}\n' + '''import json, sys
from pathlib import Path
if '-e' in sys.argv:
    print('{}')
else:
    worker = Path(sys.argv[2])
    assert worker.is_file()
    output = Path(sys.argv[-1])
    if worker.name == 'qualify-corpus.R':
        assert (Path(sys.argv[3]) / 'dtatools').is_dir()
        inputs = json.loads(Path(sys.argv[4]).read_text())
        records = [dict(id=r['id'], reader=r['reader'], status='ok',
            rows=3, columns=1, signature='test', warnings=[]) for r in inputs]
        output.write_text(''.join(json.dumps(r) + '\\n' for r in records))
    else:
        job = json.loads(Path(sys.argv[3]).read_text())
        assert (Path(job['library']) / 'dtatools').is_dir()
        if worker.name == 'worker.R':
            result = dict(signature='test', rows=job['rows'], columns=job['columns'], warnings=[])
        else:
            result = dict(result=1, load_seconds=0.01, elapsed_seconds=0.01,
                workflow_seconds=0.02, cpu_seconds=0.01, native_before=None, native_after=None)
        output.write_text(json.dumps(result))
''')
            rscript.chmod(0o755)
            (root / 'stata').write_text('Unused in semantic qualification')
            (root / 'library' / 'dtatools').mkdir(parents=True)
            description = root / 'library' / 'dtatools' / 'DESCRIPTION'
            description.write_text('Package: dtatools\n')
            (root / 'build.json').write_text(json.dumps(dict(source_commit='test', package_tree='test',
                installed={'DESCRIPTION': driver.sha(description)})))
            data = root / 'input.dta'
            data.write_bytes(b'path-handling fixture')
            (root / 'cases.json').write_text(json.dumps([dict(id='all', dta=str(data), arrow=str(data),
                selection_mode='all', selection=[], rows=3, columns=1)]))
            (root / 'inputs.json').write_text(json.dumps([dict(id='one', path=str(data), reader='read_dta')]))
            common = ['--baseline-library', 'library', '--baseline-build', 'build.json',
                      '--candidate-library', 'library', '--candidate-build', 'build.json']
            environment = os.environ | {'PATH': str(binary) + os.pathsep + os.environ.get('PATH', '')}
            scenarios = [
                ('run.py', ['--cases', 'cases.json', '--stata', 'stata', '--qualify-only'], 'qualification.json'),
                ('downstream.py', ['--cases', 'cases.json', '--case', 'all', '--repetitions', '2'], 'summary.csv'),
                ('qualify-corpus.py', ['--inputs', 'inputs.json'], 'summary.json'),
            ]
            for script, arguments, result in scenarios:
                with self.subTest(script=script):
                    output = script.removesuffix('.py')
                    run = subprocess.run([sys.executable, str(driver.HERE / script), *common,
                        *arguments, '--output', output], cwd=root, env=environment,
                        capture_output=True, text=True, timeout=30)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    self.assertTrue((root / output / result).is_file())

    def test_balanced_positions_and_pair_order(self):
        methods = ['base-dta', 'base-arrow', 'candidate-dta', 'candidate-arrow', 'stata']
        orders = driver.orders(methods, 20)
        for method in methods:
            for position in range(5):
                self.assertEqual(sum(order[position] == method for order in orders), 4)
        for a in methods:
            for b in methods:
                if a != b:
                    self.assertEqual(sum(order.index(a) < order.index(b) for order in orders), 10)

    def test_screen_zero_timers_and_losing_cohort_cannot_pass(self):
        rows = []
        for cohort, candidate in ((1, 0.9), (2, 1.1)):
            for method, elapsed in (('stata', 1.0), ('candidate-dta', candidate)):
                rows.extend(dict(case='all', mode='fresh', cohort=cohort, method=method,
                    elapsed_seconds=elapsed, peak_rss_bytes=10, cpu_seconds=1) for _ in range(12))
        screen = driver.summaries(rows, False)
        self.assertFalse(any(r['parity'] for r in screen))
        result = driver.summaries(rows, True)
        self.assertEqual([r['parity'] for r in result if r['method'] == 'candidate-dta'], [True, False])
        for row in rows:
            row['elapsed_seconds'] = 0
        self.assertFalse(any(r['parity'] for r in driver.summaries(rows, True)))
        for row in rows:
            row['elapsed_seconds'] = 0.001 if row['method'] == 'candidate-dta' else 1.0
        self.assertFalse(any(r['parity'] for r in driver.summaries(rows, True)
                             if r['method'] == 'candidate-dta'))

    def test_discovery_is_timed_and_direct_projection_is_direct(self):
        case = dict(dta='/tmp/input.dta', selection=['a', 'b'], selection_mode='known', rows=10, columns=2)
        direct = driver.stata_program(case, 'fresh', 1, Path('/tmp/out'))
        self.assertIn('use a b using', direct)
        self.assertNotIn('describe using', direct)
        case['selection_mode'] = 'any_of'
        discovery = driver.stata_program(case, 'fresh', 1, Path('/tmp/out'))
        self.assertLess(discovery.index('timer on'), discovery.index('describe using'))
        self.assertLess(discovery.index('describe using'), discovery.index('timer off'))


if __name__ == '__main__':
    unittest.main()

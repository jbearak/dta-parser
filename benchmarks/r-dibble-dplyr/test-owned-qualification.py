"""Exercise the qualification CLI with synthetic subprocess outputs, never R timings."""
import csv
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

RUNNERS = ['helpers.R', 'owned-double-helpers.R', 'owned-double.R',
           'owned-double-memory.R']
COUNTS = {'owned-double.csv': 46, 'owned-after-read.csv': 30,
          'owned-double-writes.csv': 6}


def child():
    """Execute the real driver, substituting only external measurement processes."""
    driver, repo_arg, scenario, *arguments = sys.argv[2:]
    repo = Path(repo_arg)
    original_run = subprocess.run

    def measured(command, **kwargs):
        if command[0] == 'git':
            return original_run(command, **kwargs)
        if command[0] not in ['Rscript', '/usr/bin/time']:
            raise RuntimeError(f'Unexpected child command: {command}')
        identities = [
            f'runner_md5 benchmarks/r-dibble-dplyr/{name} '
            f'{hashlib.md5((repo / "benchmarks/r-dibble-dplyr" / name).read_bytes()).hexdigest()}'
            for name in RUNNERS
        ]
        text = '\n'.join(identities) + '\n'
        if scenario == 'identity':
            text = text.replace('runner_md5', 'wrong_md5', 1)
        if command[0] == 'Rscript':
            output = Path(command[4])
            (output / 'owned-double-session.txt').write_text(text)
            for name, count in COUNTS.items():
                if scenario == name:
                    count -= 1
                with (output / name).open('w') as file:
                    writer = csv.writer(file)
                    writer.writerow(['synthetic_row'])
                    writer.writerows([[i] for i in range(count)])
        else:
            if scenario != 'rss':
                text += ' 123456 maximum resident set size\n'
            kwargs['stdout'].write(text)
        if scenario == 'final_source':
            (repo / 'benchmarks/r-dibble-dplyr/helpers.R').write_text('changed\n')
        return subprocess.CompletedProcess(command, 9 if scenario == 'command' else 0)

    sys.argv = [driver, *arguments]
    with patch('subprocess.run', measured):
        runpy.run_path(driver, run_name='__main__')


class QualificationCliTests(unittest.TestCase):
    """Prove CLI rejection and preservation under all supported optimization modes."""

    def test_guards(self):
        driver = Path(__file__).with_name('run-owned-qualification.py').resolve()
        modes = [('default', [], None), ('-O', ['-O'], None),
                 ('PYTHONOPTIMIZE=1', [], '1')]
        cases = ['success', 'source', 'command', 'identity', *COUNTS,
                 'final_source', 'existing_output', 'manifest_source',
                 'manifest_runner', 'manifest_hash', 'manifest_library',
                 'manifest_mode', 'memory_cases', 'existing_memory_log', 'rss']
        for mode, flags, optimize in modes:
            for case in cases:
                with self.subTest(mode=mode, case=case), tempfile.TemporaryDirectory() as temp:
                    root = Path(temp)
                    repo = root / 'repo'
                    runner_dir = repo / 'benchmarks/r-dibble-dplyr'
                    runner_dir.mkdir(parents=True)
                    for name in RUNNERS:
                        (runner_dir / name).write_text(f'# Synthetic fixture for {name}\n')
                    def git(*args):
                        return subprocess.check_output(['git', *args], cwd=repo,
                                                       stderr=subprocess.STDOUT).decode().strip()
                    git('init', '-q')
                    git('add', '.')
                    git('-c', 'user.name=Qualification test', '-c',
                        'user.email=qualification@example.invalid', 'commit', '-qm', 'fixture')
                    sha = git('rev-parse', 'HEAD')
                    output = root / 'output'
                    library = root / 'library'
                    env = os.environ.copy()
                    env.pop('PYTHONOPTIMIZE', None)
                    env['PYTHONDONTWRITEBYTECODE'] = '1'
                    if optimize:
                        env['PYTHONOPTIMIZE'] = optimize
                    def execute(kind, scenario):
                        return subprocess.run(
                            [sys.executable, *flags, str(Path(__file__).resolve()), '--child',
                             str(driver), str(repo), scenario, kind, str(repo), str(output),
                             str(library), 'package-source', sha, 'candidate'],
                            env=env, text=True, capture_output=True)
                    memory = case.startswith('manifest_') or case in [
                        'success', 'memory_cases', 'existing_memory_log', 'rss']
                    if memory:
                        result = execute('operations', 'success')
                        self.assertEqual(result.returncode, 0, result.stderr)
                        manifest_path = output / 'root-manifest.json'
                        manifest = json.loads(manifest_path.read_text())
                        fields = {'manifest_source': 'source_sha',
                                  'manifest_runner': 'runner_source_sha',
                                  'manifest_hash': 'runner_sha256',
                                  'manifest_library': 'library', 'manifest_mode': 'mode'}
                        if case in fields:
                            manifest[fields[case]] = 'wrong'
                        if case == 'memory_cases':
                            manifest['memory_cases'] = ['existing']
                        manifest_path.write_text(json.dumps(manifest))
                        if case == 'existing_memory_log':
                            (output / 'memory-rename-100000.log').write_text('preserve this log\n')
                    if case == 'source':
                        (runner_dir / 'helpers.R').write_text('different\n')
                    if case == 'existing_output':
                        output.mkdir()
                        (output / 'sentinel').write_text('preserve this output\n')
                    before = {p.name: p.read_bytes() for p in output.glob('*')} if output.exists() else {}
                    result = execute('memory' if memory else 'operations', case)
                    if case == 'success':
                        self.assertEqual(result.returncode, 0, result.stderr)
                        final = json.loads((output / 'root-manifest.json').read_text())
                        self.assertEqual(len(final['memory_cases']), 6)
                    else:
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertIn('RuntimeError:', result.stderr)
                        if case == 'source':
                            self.assertIn('Runner source mismatch:', result.stderr)
                            self.assertFalse(output.exists())
                        for name, content in before.items():
                            self.assertEqual((output / name).read_bytes(), content, name)
                        if not memory:
                            self.assertFalse((output / 'root-manifest.json').exists())
                    print(f'PASS {mode}: {case}', flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--child':
        child()
    else:
        unittest.main()

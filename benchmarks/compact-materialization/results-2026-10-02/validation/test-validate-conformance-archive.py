"""Small rejection checks for the published conformance source binding."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


CHECKER = Path(sys.argv.pop(1)).resolve()
PASS = 'R package conformance: PASS (current source built and checked with offline Cargo archive)'


class ArchiveBindingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / 'repository'
        self.repository.mkdir()
        self.package = self.repository / 'r-package/dtatools'
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith('GIT_')}
        self.sources = {'src/example.c': b'int example;\n', 'R/read.R': b'identity\n',
                        'tests/test.R': b'stopifnot(TRUE)\n', 'tools/check.R': b'quit()\n'}
        for name, data in {**self.sources, 'src/dta-tools/examples/a.rs': b'ignored\n',
                           '.Rbuildignore': b'^src/dta-tools/examples$\n'}.items():
            path = self.package / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        for args in (['init', '-q'], ['add', '.'], ['-c', 'user.name=Archive test',
                '-c', 'user.email=archive@example.invalid', 'commit', '-qm', 'fixture']):
            subprocess.run(['git', *args], cwd=self.repository, env=self.environment,
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'],
            cwd=self.repository, env=self.environment, text=True).strip()
        self.prefix = self.root / 'conformance'
        self.prefix.with_suffix('.log').write_text(PASS + '\n')

    def archive(self, sources=None, extra=None):
        with tarfile.open(self.prefix.with_suffix('.tar.gz'), 'w:gz') as archive:
            for name, data in (self.sources if sources is None else sources).items():
                member = tarfile.TarInfo('dtatools/' + name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            if extra is not None:
                archive.addfile(extra, io.BytesIO(b'x') if extra.isfile() else None)

    def run_checker(self, environment=None):
        return subprocess.run([sys.executable, str(CHECKER), str(self.repository),
            str(self.package), str(self.prefix), self.commit], env=environment,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_exact_inventory_and_inherited_git_overrides(self):
        self.archive()
        environment = dict(self.environment, GIT_DIR='/does/not/exist',
            GIT_WORK_TREE='/also/wrong', GIT_COMMON_DIR='/wrong/common',
            GIT_OBJECT_DIRECTORY='/wrong/objects', GIT_INDEX_FILE='/wrong/index')
        result = self.run_checker(environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(self.prefix.with_suffix('.json').read_text())
        self.assertEqual(set(record['verified_files']), set(self.sources))
        self.assertEqual(record['deliberately_excluded_by_buildignore'],
                         ['src/dta-tools/examples/a.rs'])
        self.assertTrue(record['exact_packaged_source_inventory'])

    def test_extra_untracked_source_rejected(self):
        self.archive({**self.sources, 'src/untracked.c': b'extra\n'})
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected packaged source: src/untracked.c', result.stderr)

    def test_excluded_source_present_rejected(self):
        self.archive({**self.sources, 'src/dta-tools/examples/a.rs': b'ignored\n'})
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected packaged source: src/dta-tools/examples/a.rs', result.stderr)

    def test_missing_source_rejected(self):
        self.archive({name: data for name, data in self.sources.items() if name != 'R/read.R'})
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing packaged source: R/read.R', result.stderr)

    def test_changed_source_rejected(self):
        self.archive({**self.sources, 'R/read.R': b'changed\n'})
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Checked source mismatch: R/read.R', result.stderr)

    def test_duplicate_source_rejected(self):
        extra = tarfile.TarInfo('dtatools/src/example.c')
        extra.size = 1
        self.archive(extra=extra)
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate packaged source: src/example.c', result.stderr)

    def test_non_regular_source_rejected(self):
        extra = tarfile.TarInfo('dtatools/src/link.c')
        extra.type = tarfile.SYMTYPE
        extra.linkname = 'example.c'
        self.archive(extra=extra)
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Non-regular packaged source: src/link.c', result.stderr)

    def test_source_root_symlink_rejected(self):
        for root in ('src', 'R', 'tests', 'tools'):
            extra = tarfile.TarInfo('dtatools/' + root)
            extra.type = tarfile.SYMTYPE
            extra.linkname = 'elsewhere'
            self.archive(extra=extra)
            result = self.run_checker()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Non-regular packaged source: ' + root, result.stderr)

    def test_mutated_export_and_matching_archive_rejected(self):
        (self.package / 'R/read.R').write_bytes(b'changed after commit\n')
        self.archive({**self.sources, 'R/read.R': b'changed after commit\n'})
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Clean export differs from source commit: R/read.R', result.stderr)

    def test_changed_buildignore_rejected(self):
        (self.package / '.Rbuildignore').write_bytes(b'^src$\n')
        self.archive()
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Clean export differs from source commit: .Rbuildignore', result.stderr)


if __name__ == '__main__':
    unittest.main()

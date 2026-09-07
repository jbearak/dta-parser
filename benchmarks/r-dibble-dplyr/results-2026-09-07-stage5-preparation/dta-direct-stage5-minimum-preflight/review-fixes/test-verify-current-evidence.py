"""Bounded corruption tests for the new current-copy evidence index."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('current_evidence', Path(__file__).with_name('verify-current-evidence.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class CurrentEvidence(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.names = sorted([guard.ARCHIVE + '/dplyr-r46-minimum.md', *guard.DOCS])
        for name in self.names:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('historical note\n')
        self.write_index()

    def row(self, name):
        path = self.root/name
        return dict(path=name, bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                    sha256=hashlib.sha256(path.read_bytes()).hexdigest())

    def write_index(self, rows=None):
        index = self.root/guard.INDEX
        index.write_text(json.dumps(dict(excluded=sorted(guard.EXCLUDED), files=rows if rows is not None else [self.row(n) for n in self.names])))
        (self.root/guard.RECEIPT).write_text(json.dumps(dict(status='complete', index=self.row(guard.INDEX))))

    def test_exact_copy(self):
        self.assertEqual(guard.verify(self.root)['files'], 3)

    def test_promoted_note_changed(self):
        (self.root/guard.ARCHIVE/'dplyr-r46-minimum.md').write_text('altered note\n')
        with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
            guard.verify(self.root)

    def test_extra_archive_file(self):
        (self.root/guard.ARCHIVE/'unexpected.R').write_text('stop()')
        with self.assertRaisesRegex(RuntimeError, 'inventory'):
            guard.verify(self.root)

    def test_missing_file(self):
        (self.root/self.names[0]).unlink()
        with self.assertRaises((RuntimeError, FileNotFoundError)):
            guard.verify(self.root)

    def test_identical_byte_symlink(self):
        path = self.root/guard.ARCHIVE/'dplyr-r46-minimum.md'
        path.unlink()
        path.symlink_to(self.root/'docs/research/dplyr-r46-minimum.md')
        with self.assertRaisesRegex(RuntimeError, 'Link or special'):
            guard.verify(self.root)

    def test_duplicate_indexed_path(self):
        rows = [self.row(n) for n in self.names]
        self.write_index(rows + rows[:1])
        with self.assertRaisesRegex(RuntimeError, 'Duplicate'):
            guard.verify(self.root)

    def test_unbound_index(self):
        with (self.root/guard.INDEX).open('a') as stream:
            stream.write(' ')
        with self.assertRaisesRegex(RuntimeError, 'does not bind'):
            guard.verify(self.root)

    def test_out_of_scope_record(self):
        rows = [self.row(n) for n in self.names]
        rows[0]['path'] = '../outside'
        self.write_index(rows)
        with self.assertRaisesRegex(RuntimeError, 'Out-of-scope'):
            guard.verify(self.root)


if __name__ == '__main__':
    unittest.main(verbosity=2)

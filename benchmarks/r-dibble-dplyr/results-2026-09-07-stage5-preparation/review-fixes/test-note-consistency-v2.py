"""Corruption witnesses use temporary copies of the six named inputs only."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('note_check', HERE / 'verify-note-consistency-v2.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class NoteConsistencyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in check.INPUTS:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HERE.parent / name, target)

    def alter(self, name):
        path = self.root / name
        path.write_bytes(path.read_bytes() + b'\nchanged\n')

    def test_current_notes_pass(self):
        self.assertEqual(check.verify(self.root)['status'], 'pass')

    def test_changed_promoted_note(self):
        self.alter(check.PROMOTED)
        with self.assertRaisesRegex(RuntimeError, 'Note differs'):
            check.verify(self.root)

    def test_changed_raw_note(self):
        self.alter(check.RAW)
        with self.assertRaisesRegex(RuntimeError, 'Note differs'):
            check.verify(self.root)

    def test_both_notes_changed_identically(self):
        self.alter(check.RAW)
        self.alter(check.PROMOTED)
        with self.assertRaisesRegex(RuntimeError, 'Note differs'):
            check.verify(self.root)

    def test_each_pinned_record_changed(self):
        for name in check.PINS:
            with self.subTest(name=name):
                original = (self.root / name).read_bytes()
                self.alter(name)
                with self.assertRaisesRegex(RuntimeError, 'Pinned preparation record changed'):
                    check.verify(self.root)
                (self.root / name).write_bytes(original)

    def test_changed_note_mode(self):
        legacy_spec = importlib.util.spec_from_file_location(
            'legacy_note_check', HERE / 'verify-note-consistency.py')
        legacy = importlib.util.module_from_spec(legacy_spec)
        legacy_spec.loader.exec_module(legacy)
        for name in (check.RAW, check.PROMOTED):
            with self.subTest(name=name):
                path = self.root / name
                original = path.read_bytes()
                original_mode = path.stat().st_mode & 0o777
                try:
                    path.chmod(original_mode ^ 0o100)
                    self.assertEqual(path.read_bytes(), original)
                    self.assertEqual(legacy.verify(self.root)['status'], 'pass')
                    with self.assertRaisesRegex(RuntimeError, 'Inclusion note record mismatch'):
                        check.verify(self.root)
                finally:
                    path.chmod(original_mode)

    def test_missing_promoted_note(self):
        (self.root / check.PROMOTED).unlink()
        with self.assertRaises(FileNotFoundError):
            check.verify(self.root)

    def test_identical_note_symlink(self):
        (self.root / check.PROMOTED).unlink()
        (self.root / check.PROMOTED).symlink_to(self.root / check.RAW)
        with self.assertRaisesRegex(RuntimeError, 'Symlink'):
            check.verify(self.root)


if __name__ == '__main__':
    unittest.main(verbosity=2)

"""Corruption witnesses use temporary copies of the six named inputs only."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('note_check', HERE / 'verify-note-consistency.py')
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
            shutil.copyfile(HERE.parent / name, target)

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

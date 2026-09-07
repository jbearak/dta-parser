"""Check that accepted artifact identities cannot be rebound as fresh inputs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('control', HERE / 'read-control-v2.py')
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


class AcceptedBuildBindings(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / 'artifact.json'
        self.path.write_text('{"accepted": true}\n')
        self.expected = control.identity(self.path)

    def test_unchanged_record(self):
        control.require_expected_records([control.identity(self.path)], [self.expected])
        self.assertEqual(control.read_bound_json(self.path, self.expected), {'accepted': True})

    def test_changed_artifact_cannot_be_rebound(self):
        self.path.write_text('{"accepted": false}\n')
        with self.assertRaisesRegex(RuntimeError, 'no longer matches'):
            control.require_expected_records([control.identity(self.path)], [self.expected])

    def test_changed_record_rejected_before_parse(self):
        self.path.write_text('invalid JSON')
        with self.assertRaisesRegex(RuntimeError, 'changed before consumption'):
            control.read_bound_json(self.path, self.expected)

    def test_changed_mode(self):
        self.path.chmod(self.path.stat().st_mode ^ 0o100)
        with self.assertRaisesRegex(RuntimeError, 'no longer matches'):
            control.require_expected_records([control.identity(self.path)], [self.expected])

    def test_missing_bound_path(self):
        with self.assertRaisesRegex(RuntimeError, 'no longer matches'):
            control.require_expected_records([], [self.expected])

    def test_duplicate_bound_path(self):
        with self.assertRaisesRegex(RuntimeError, 'Duplicate'):
            control.require_expected_records([self.expected, self.expected], [self.expected])

    def test_identical_bytes_at_different_resolved_path(self):
        second = self.root / 'second.json'
        second.write_bytes(self.path.read_bytes())
        link = self.root / 'link.json'
        link.symlink_to(self.path)
        original = control.identity(link)
        link.unlink()
        link.symlink_to(second)
        with self.assertRaisesRegex(RuntimeError, 'no longer matches'):
            control.require_expected_records([control.identity(link)], [original])

    def test_missing_input_detected_before_launch_or_finally(self):
        self.path.unlink()
        changes = control.input_changes([self.expected])
        self.assertEqual(len(changes), 1)
        self.assertIn('error', changes[0])


if __name__ == '__main__':
    unittest.main(verbosity=2)

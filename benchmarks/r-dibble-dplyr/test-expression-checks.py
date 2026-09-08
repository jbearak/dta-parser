"""Integrity failures must remain diagnosable before and after a check run."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('expression_checks', Path(__file__).with_name('run-expression-checks.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class IntegrityTests(unittest.TestCase):
    def test_existing_and_dangling_output_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            for path in [root, root/'file', root/'dangling']:
                if path.name == 'file':
                    path.write_text('existing')
                if path.name == 'dangling':
                    path.symlink_to(root/'absent')
                with self.assertRaisesRegex(RuntimeError, 'Fresh output required'):
                    checks.require_fresh(path)
            checks.require_fresh(root/'new')
            self.assertFalse((root/'absent').exists())

    def test_deleted_and_changed_inputs_are_recorded(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/'input'
            path.write_text('before')
            before = [checks.identity(path)]
            self.assertEqual(checks.input_changes(before), [])
            path.write_text('after')
            changed = checks.input_changes(before)
            self.assertEqual(changed[0]['path'], str(path))
            self.assertIn('current', changed[0])
            path.unlink()
            missing = checks.input_changes(before)
            self.assertEqual(missing[0]['path'], str(path))
            self.assertIn('error', missing[0])

    def test_new_package_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            original = root/'original.R'
            original.write_text('1')
            expected = {original}
            checks.require_package_inventory(root, expected)
            (root/'new.R').write_text('2')
            with self.assertRaisesRegex(RuntimeError, 'Package source inventory changed'):
                checks.require_package_inventory(root, expected)


if __name__ == '__main__':
    unittest.main()

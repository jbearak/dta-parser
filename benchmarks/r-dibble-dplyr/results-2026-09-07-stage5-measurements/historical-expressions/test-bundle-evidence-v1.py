"""Exercise evidence consistency failures with disposable synthetic records."""
from pathlib import Path
import importlib.util
import io
import json
import tarfile
import tempfile
import unittest

RECIPE = Path(__file__).with_name('bundle-evidence-v1.py')
spec = importlib.util.spec_from_file_location('bundle', RECIPE)
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='stage5-bundle-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.rows = []
        for name, data, mode, presentation in [
            ('code/runner.py', b'print(1)\n', 0o755, 'plain'),
            ('raw/value.rds', bytes(range(256)), 0o640, 'bundle'),
        ]:
            source = self.root / 'inputs' / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(data)
            source.chmod(mode)
            self.rows.append(dict(source=str(source), path=name,
                                  presentation=presentation, **bundle.identity(source)))
        self.selection = self.root / 'selected.json'
        self.selection.write_text(json.dumps(dict(files=self.rows)))
        self.output = self.root / 'output'

    def build(self):
        return bundle.create(self.selection, self.output)

    def replace_tar(self, members):
        # Creation also verifies members before a receipt exists. Exercise that
        # check directly instead of stopping at the final archive digest guard.
        (self.output / 'bundle-receipt.json').unlink()
        with tarfile.open(self.output / 'records.tar.gz', 'w:gz') as archive:
            for name, data, kind in members:
                info = tarfile.TarInfo(name)
                info.mode = 0o640
                info.type = kind
                if kind == tarfile.REGTYPE:
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
                else:
                    info.linkname = '../../outside'
                    archive.addfile(info)

    def test_binary_and_modes_survive(self):
        receipt = self.build()
        self.assertEqual(receipt['plain_files'], 1)
        self.assertEqual(receipt['bundled_files'], 1)
        self.assertEqual(bundle.verify(self.output)['selected_bytes'], 265)
        self.assertEqual((self.output / 'code/runner.py').stat().st_mode & 0o777, 0o755)

    def test_existing_output_refused(self):
        self.build()
        with self.assertRaisesRegex(ValueError, 'Fresh destination'):
            self.build()

    def test_changed_input_refused_before_output(self):
        Path(self.rows[0]['source']).write_bytes(b'changed\n')
        with self.assertRaisesRegex(ValueError, 'differs from selection'):
            self.build()
        self.assertFalse(self.output.exists())

    def test_extra_plain_file_refused(self):
        self.build()
        (self.output / 'unexpected').write_text('extra')
        with self.assertRaisesRegex(ValueError, 'plain-file inventory'):
            bundle.verify(self.output)

    def test_changed_plain_file_refused(self):
        self.build()
        (self.output / 'code/runner.py').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'differs from selection'):
            bundle.verify(self.output)

    def test_changed_archive_receipt_guard(self):
        self.build()
        with (self.output / 'records.tar.gz').open('ab') as stream:
            stream.write(b'extra')
        with self.assertRaisesRegex(ValueError, 'differs from selection'):
            bundle.verify(self.output)

    def test_changed_member_content_refused(self):
        self.build()
        self.replace_tar([('raw/value.rds', b'x' * 256, tarfile.REGTYPE)])
        with self.assertRaisesRegex(ValueError, 'content differs'):
            bundle.verify(self.output)

    def test_missing_member_refused(self):
        self.build()
        self.replace_tar([])
        with self.assertRaisesRegex(ValueError, 'Missing tar members'):
            bundle.verify(self.output)

    def test_duplicate_member_refused(self):
        self.build()
        member = ('raw/value.rds', bytes(range(256)), tarfile.REGTYPE)
        self.replace_tar([member, member])
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            bundle.verify(self.output)

    def test_link_member_refused(self):
        self.build()
        self.replace_tar([('raw/value.rds', b'', tarfile.SYMTYPE)])
        with self.assertRaisesRegex(ValueError, 'nonregular'):
            bundle.verify(self.output)

    def test_parent_path_refused(self):
        self.rows[0]['path'] = '../outside'
        self.selection.write_text(json.dumps(dict(files=self.rows)))
        with self.assertRaisesRegex(ValueError, 'Noncanonical'):
            self.build()
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)

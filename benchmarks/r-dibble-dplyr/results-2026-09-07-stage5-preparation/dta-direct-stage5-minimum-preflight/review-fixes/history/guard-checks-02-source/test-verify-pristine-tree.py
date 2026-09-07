"""Bounded synthetic regressions for the new pre-build replay guard."""
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('pristine_guard', Path(__file__).with_name('verify-pristine-tree.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class TreeChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root/'source.tar'
        self.tree = self.root/'tree'
        self.tree.mkdir()
        (self.tree/'pkg').mkdir()
        (self.tree/'pkg/code.R').write_bytes(b'x <- 1\n')
        (self.tree/'pkg/code.R').chmod(0o644)
        (self.tree/'pkg').chmod(0o755)
        self.build_archive()

    def build_archive(self, extra=None):
        with tarfile.open(self.archive, 'w') as tar:
            directory = tarfile.TarInfo('pkg')
            directory.type = tarfile.DIRTYPE
            directory.mode = 0o755
            tar.addfile(directory)
            member = tarfile.TarInfo('pkg/code.R')
            member.size = len(b'x <- 1\n')
            member.mode = 0o644
            tar.addfile(member, io.BytesIO(b'x <- 1\n'))
            if extra is not None:
                tar.addfile(extra, io.BytesIO(b'') if extra.isfile() else None)
        self.sha = hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def check(self):
        return guard.verify(self.archive, self.tree, self.sha)

    def test_exact_tree(self):
        self.assertEqual(self.check()['files'], 1)

    def test_extra_r_source(self):
        (self.tree/'pkg/injected.R').write_text('stop("extra")')
        with self.assertRaisesRegex(RuntimeError, 'inventory mismatch'):
            self.check()

    def test_extra_makevars(self):
        (self.tree/'pkg/Makevars').write_text('OBJECTS=extra.o')
        with self.assertRaisesRegex(RuntimeError, 'inventory mismatch'):
            self.check()

    def test_extra_empty_directory(self):
        (self.tree/'pkg/extra').mkdir()
        with self.assertRaisesRegex(RuntimeError, 'inventory mismatch'):
            self.check()

    def test_missing_member(self):
        (self.tree/'pkg/code.R').unlink()
        with self.assertRaisesRegex(RuntimeError, 'inventory mismatch'):
            self.check()

    def test_changed_bytes_same_length(self):
        (self.tree/'pkg/code.R').write_bytes(b'x <- 2\n')
        with self.assertRaisesRegex(RuntimeError, 'content mismatch'):
            self.check()

    def test_changed_mode(self):
        (self.tree/'pkg/code.R').chmod(0o755)
        with self.assertRaisesRegex(RuntimeError, 'mode mismatch'):
            self.check()

    def test_symlink_to_identical_external_bytes(self):
        outside = self.root/'outside'
        outside.write_bytes(b'x <- 1\n')
        (self.tree/'pkg/code.R').unlink()
        (self.tree/'pkg/code.R').symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError, 'Link or special'):
            self.check()

    def test_broken_symlink(self):
        (self.tree/'pkg/broken').symlink_to(self.root/'missing')
        with self.assertRaisesRegex(RuntimeError, 'Link or special'):
            self.check()

    def test_directory_symlink(self):
        (self.tree/'pkg/linked').symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'Link or special'):
            self.check()

    def test_symlink_tree_root(self):
        alias = self.root/'alias'
        alias.symlink_to(self.tree, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'real directory'):
            guard.verify(self.archive, alias, self.sha)

    def test_wrong_archive_digest(self):
        with self.assertRaisesRegex(RuntimeError, 'SHA-256 mismatch'):
            guard.verify(self.archive, self.tree, '0'*64)

    def test_duplicate_archive_member(self):
        self.build_archive(tarfile.TarInfo('pkg/code.R'))
        with self.assertRaisesRegex(RuntimeError, 'Duplicate archive'):
            self.check()

    def test_archive_path_escape(self):
        self.build_archive(tarfile.TarInfo('../escape'))
        with self.assertRaisesRegex(RuntimeError, 'Unsafe or noncanonical'):
            self.check()

    def test_archive_symlink(self):
        member = tarfile.TarInfo('pkg/link')
        member.type = tarfile.SYMTYPE
        member.linkname = 'code.R'
        self.build_archive(member)
        with self.assertRaisesRegex(RuntimeError, 'Unsupported archive'):
            self.check()


if __name__ == '__main__':
    unittest.main(verbosity=2)

"""Exercise the installer boundary without compiling or loading an R package."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


INSTALLER = Path(__file__).resolve().parents[1] / "benchmarks/reader-refresh/install.py"


class ReaderInstallTests(unittest.TestCase):
    """A build record must identify clean, tracked package source."""

    def setUp(self):
        """Create a private Git checkout and a minimal external build stand-in."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.package = self.source / "r-package/dtatools"
        (self.package / "R").mkdir(parents=True)
        (self.package / "DESCRIPTION").write_text("Package: dtatools\n")
        self.git("init", "--quiet")
        self.git("add", "r-package")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "commit", "--quiet", "-m", "Tracked source")
        self.library = self.root / "library"
        self.record = self.root / "build.json"
        self.executed = self.root / "builder-ran"
        binary = self.root / "bin"
        binary.mkdir()
        builder = binary / "R"
        builder.write_text(
            "#!" + sys.executable + "\n"
            "import os, pathlib, sys\n"
            "pathlib.Path(os.environ['READER_TEST_BUILDER_MARKER']).touch()\n"
            "library = next(a.split('=', 1)[1] for a in sys.argv if a.startswith('--library='))\n"
            "package = pathlib.Path(library) / 'dtatools'\n"
            "package.mkdir()\n"
            "(package / 'DESCRIPTION').write_text('test installation')\n"
        )
        builder.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                                READER_TEST_BUILDER_MARKER=str(self.executed))

    def git(self, *arguments):
        """Run Git only in the test-owned checkout."""
        return subprocess.check_output(["git", *arguments], cwd=self.source, text=True).strip()

    def install(self):
        """Invoke the real installer with the test-owned external builder."""
        return subprocess.run([sys.executable, "-O", str(INSTALLER), str(self.source),
                               str(self.library), str(self.record)], env=self.environment,
                              capture_output=True, text=True)

    def test_clean_source_binds_the_completed_installation(self):
        """A successful build records both source identity and installed bytes."""
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(self.record.read_text())
        self.assertEqual(record["source_commit"], self.git("rev-parse", "HEAD"))
        self.assertEqual(record["package_tree"], self.git("rev-parse", "HEAD:r-package/dtatools"))
        self.assertEqual(record["installed"], {
            "DESCRIPTION": hashlib.sha256(b"test installation").hexdigest()
        })

    def test_untracked_package_source_never_reaches_the_builder(self):
        """An uncommitted new R function must not produce a trusted build record."""
        (self.package / "R/untracked.R").write_text("new_function <- function() 1\n")
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("untracked package source", result.stderr)
        self.assertFalse(self.executed.exists())
        self.assertFalse(self.record.exists())

    def test_modified_tracked_source_never_reaches_the_builder(self):
        """Tracked edits must also prevent installation and publication."""
        (self.package / "DESCRIPTION").write_text("Package: changed\n")
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.executed.exists())
        self.assertFalse(self.record.exists())


if __name__ == "__main__":
    unittest.main()

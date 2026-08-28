#!/usr/bin/env python3
"""Mutation tests for R source-package archive validation."""

from __future__ import annotations

import importlib.util
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("check_r_package_archive.py")
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("check_r_package_archive", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
archive_check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive_check)

REQUIRED_FIXTURE_FILES = {
    "dtatools/src/dta-tools/Cargo.toml",
    "dtatools/src/dta-tools/src/lib.rs",
    "dtatools/src/rust/Cargo.toml",
    "dtatools/src/rust/Cargo.lock",
    "dtatools/src/rust/vendor.tar.gz",
    "dtatools/src/Makevars.rust",
    "dtatools/tools/configure-rust.sh",
    "dtatools/tools/rust-source-hash.R",
}


class PackageArchiveTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.archive = Path(temporary.name) / "dtatools.tar.gz"

    def write_archive(
        self,
        *,
        replacement: tuple[str, tarfile.TarInfo] | None = None,
        extra: tarfile.TarInfo | None = None,
        omit: str | None = None,
    ) -> None:
        with tarfile.open(self.archive, mode="w:gz") as destination:
            for name in sorted(REQUIRED_FIXTURE_FILES):
                if name == omit:
                    continue
                member = (
                    replacement[1]
                    if replacement is not None and name == replacement[0]
                    else tarfile.TarInfo(name)
                )
                if member.isfile():
                    member.size = 0
                    destination.addfile(member, io.BytesIO())
                else:
                    destination.addfile(member)
            if extra is not None:
                if extra.isfile():
                    extra.size = 0
                    destination.addfile(extra, io.BytesIO())
                else:
                    destination.addfile(extra)

    def test_valid_required_files_pass(self) -> None:
        self.write_archive()
        archive_check.check_archive(self.archive)

    def test_every_required_file_is_enforced(self) -> None:
        self.assertEqual(archive_check.REQUIRED_FILES, REQUIRED_FIXTURE_FILES)
        for name in sorted(REQUIRED_FIXTURE_FILES):
            with self.subTest(name=name):
                self.write_archive(omit=name)
                with self.assertRaisesRegex(
                    archive_check.ArchiveError, "missing regular file"
                ):
                    archive_check.check_archive(self.archive)

    def test_required_file_must_not_be_a_symlink(self) -> None:
        name = "dtatools/tools/configure-rust.sh"
        link = tarfile.TarInfo(name)
        link.type = tarfile.SYMTYPE
        link.linkname = "/tmp/attacker-controlled-script"
        self.write_archive(replacement=(name, link))
        with self.assertRaisesRegex(archive_check.ArchiveError, "special entry"):
            archive_check.check_archive(self.archive)

    def test_member_paths_must_be_canonical_and_inside_package(self) -> None:
        for name in ("outside", "dtatools/src/../outside", "dtatools//file"):
            with self.subTest(name=name):
                self.write_archive(extra=tarfile.TarInfo(name))
                with self.assertRaisesRegex(archive_check.ArchiveError, "unsafe path"):
                    archive_check.check_archive(self.archive)

    def test_cross_platform_path_aliases_fail(self) -> None:
        alias = tarfile.TarInfo("dtatools/tools/CONFIGURE-RUST.SH")
        self.write_archive(extra=alias)
        with self.assertRaisesRegex(archive_check.ArchiveError, "paths collide"):
            archive_check.check_archive(self.archive)

    def test_excluded_build_files_fail(self) -> None:
        self.write_archive(extra=tarfile.TarInfo("dtatools/src/rust/target/output"))
        with self.assertRaisesRegex(archive_check.ArchiveError, "excluded Rust"):
            archive_check.check_archive(self.archive)


if __name__ == "__main__":
    unittest.main()

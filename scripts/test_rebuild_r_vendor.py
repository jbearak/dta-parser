#!/usr/bin/env python3
"""Focused compatibility and safety tests for the vendor repacker."""

from __future__ import annotations

import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("rebuild-r-vendor.py")
SPEC = importlib.util.spec_from_file_location("rebuild_r_vendor", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
repacker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repacker)


def archive_with(member: tarfile.TarInfo, contents: bytes = b"") -> io.BytesIO:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w") as archive:
        if member.isfile():
            member.size = len(contents)
            archive.addfile(member, io.BytesIO(contents))
        else:
            archive.addfile(member)
    output.seek(0)
    return output


class LegacyExtractionTests(unittest.TestCase):
    def extract(self, member: tarfile.TarInfo, contents: bytes = b"") -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        destination = Path(temporary.name)
        with tarfile.open(fileobj=archive_with(member, contents), mode="r:") as source:
            repacker.safe_extract(source, destination, force_legacy=True)
        return destination

    def test_extracts_a_safe_regular_file_without_filter_support(self) -> None:
        member = tarfile.TarInfo("v/example.txt")
        destination = self.extract(member, b"safe")
        self.assertEqual((destination / "v/example.txt").read_bytes(), b"safe")

    def test_rejects_absolute_and_parent_traversal_paths(self) -> None:
        for name in ["/absolute", "../escape", "v/../../escape"]:
            with self.subTest(name=name), self.assertRaises(tarfile.ExtractError):
                self.extract(tarfile.TarInfo(name), b"unsafe")

    def test_rejects_links_that_escape_the_destination(self) -> None:
        member = tarfile.TarInfo("v/link")
        member.type = tarfile.SYMTYPE
        member.linkname = "../../escape"
        with self.assertRaises(tarfile.ExtractError):
            self.extract(member)

    def test_normalizes_member_modes(self) -> None:
        directory = tarfile.TarInfo("v")
        directory.type = tarfile.DIRTYPE
        regular = tarfile.TarInfo("v/file")
        link = tarfile.TarInfo("v/link")
        link.type = tarfile.SYMTYPE
        self.assertEqual(repacker.normalize_info(directory).mode, 0o755)
        self.assertEqual(repacker.normalize_info(regular).mode, 0o644)
        self.assertEqual(repacker.normalize_info(link).mode, 0o777)


if __name__ == "__main__":
    unittest.main()

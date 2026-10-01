"""Lightweight build-record checks; no R processes, compilers, or installations."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("reader_build_records_test", HERE / "record-builds.py")
RECORDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORDS)


class SourceInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="reader-record-test-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.base = {"DESCRIPTION": b"Package: example\n", "R/read.R": b"reader <- function() 1\n"}
        self.modes = dict.fromkeys(self.base, 0o644)
        RECORDS.materialize(self.source, self.base, self.modes)
        self.expected = {name: RECORDS.sha_bytes(data) for name, data in self.base.items()}

    def tearDown(self):
        self.temporary.cleanup()

    def test_complete_source_inventory_matches(self):
        self.assertEqual(RECORDS.source_inventory(self.source, self.base), self.expected)
        self.assertEqual(RECORDS.source_modes(self.source, self.base), self.modes)

    def test_added_source_is_rejected(self):
        (self.source / "R/extra.R").write_text("extra <- TRUE\n")
        with self.assertRaisesRegex(ValueError, "unrecorded"):
            RECORDS.source_inventory(self.source, self.base)

    def test_missing_source_is_rejected(self):
        (self.source / "R/read.R").unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            RECORDS.source_inventory(self.source, self.base)

    def test_file_and_directory_symlinks_are_rejected(self):
        link = self.source / "R/link.R"
        link.symlink_to(self.source / "R/read.R")
        with self.assertRaisesRegex(ValueError, "nonordinary"):
            RECORDS.source_inventory(self.source, self.base)
        link.unlink()
        directory_link = self.source / "alias"
        directory_link.symlink_to(self.source / "R", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            RECORDS.source_inventory(self.source, self.base)

    def test_allowed_build_output_does_not_hide_new_source(self):
        (self.source / "src").mkdir()
        (self.source / "src/dtatools.so").write_bytes(b"compiled output")
        (self.source / "src/Makevars").write_text("GENERATED = yes\n")
        self.assertEqual(RECORDS.source_inventory(self.source, self.base, True), self.expected)
        (self.source / "src/extra.c").write_text("int extra;\n")
        with self.assertRaisesRegex(ValueError, "unexpected"):
            RECORDS.source_inventory(self.source, self.base, True)

    def test_build_output_is_rejected_in_preserved_snapshot(self):
        (self.source / "src").mkdir()
        (self.source / "src/dtatools.so").write_bytes(b"compiled output")
        with self.assertRaisesRegex(ValueError, "unrecorded"):
            RECORDS.source_inventory(self.source, self.base)

    def test_changed_bytes_have_a_different_fingerprint(self):
        (self.source / "R/read.R").write_text("reader <- function() 2\n")
        self.assertNotEqual(RECORDS.source_inventory(self.source, self.base), self.expected)


class PatchTests(unittest.TestCase):
    def setUp(self):
        self.base = {"R/read.R": b"reader <- function() 1\n"}
        self.modes = dict.fromkeys(self.base, 0o644)

    def test_patch_reproduces_exact_candidate(self):
        candidate = {"R/read.R": b"reader <- function() 2\n"}
        patch = RECORDS.HELPERS.text_patch(self.base, candidate)
        expected = {name: RECORDS.sha_bytes(data) for name, data in candidate.items()}
        RECORDS.replay_patch(self.base, self.modes, patch, expected)

    def test_empty_patch_reproduces_exact_baseline(self):
        expected = {name: RECORDS.sha_bytes(data) for name, data in self.base.items()}
        RECORDS.replay_patch(self.base, self.modes, "", expected)

    def test_nonreproducing_patch_is_rejected(self):
        wrong = {"R/read.R": RECORDS.sha_bytes(b"reader <- function() 3\n")}
        with self.assertRaisesRegex(ValueError, "does not reproduce"):
            RECORDS.replay_patch(self.base, self.modes, "", wrong)

    def test_malformed_patch_is_rejected(self):
        expected = {name: RECORDS.sha_bytes(data) for name, data in self.base.items()}
        with self.assertRaises(subprocess.CalledProcessError):
            RECORDS.replay_patch(self.base, self.modes, "not a patch\n", expected)

    def test_changed_binary_and_missing_final_newline_are_rejected(self):
        for changed in (b"reader <- function() 2", b"\0binary\n"):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                RECORDS.HELPERS.text_patch(self.base, {"R/read.R": changed})

    def test_private_path_in_patch_is_rejected(self):
        candidate = {"R/read.R": b'path <- "/Users/example/private-data"\n'}
        with self.assertRaisesRegex(ValueError, "private"):
            RECORDS.HELPERS.text_patch(self.base, candidate)


class PrivacyTests(unittest.TestCase):
    def test_public_records_reject_private_paths_in_arbitrary_fields(self):
        for path in ("/Users/example/source", "/private/tmp/source", "/home/example/source", "/tmp/source"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "private"):
                RECORDS.public_bytes({"notes": path})

    def test_safe_record_has_canonical_bytes(self):
        self.assertEqual(RECORDS.public_bytes({"b": 2, "a": 1}), b'{\n  "a": 1,\n  "b": 2\n}\n')


if __name__ == "__main__":
    unittest.main()

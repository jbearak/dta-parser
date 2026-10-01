"""Check the supplemental oracle adapter without running R, Stata or corpus reads."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("extra_oracle", Path(__file__).with_name("verify-extra-cache.py"))
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)


class AdapterTests(unittest.TestCase):
    def test_rejects_missing_and_ambiguous_edit_targets(self):
        for text in ("different", "target target"):
            with self.assertRaises(ValueError):
                ORACLE.replace_once(text, "target", "new")

    def test_only_changes_corpus_list_and_expected_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            before, after, patch = ORACLE.stage_sources(ORACLE.ROOT, work)
            changed = {name for name in before if before[name] != after[name]}
            self.assertEqual(changed, {"benchmarks/r-corpus-roundtrip/common.R",
                "benchmarks/r-corpus-roundtrip/verify.R"})
            staged = work / "harness/benchmarks/r-corpus-roundtrip"
            self.assertIn('c("ENADID", "WFS", "CFR")', (staged / "common.R").read_text())
            verifier = (staged / "verify.R").read_text()
            self.assertIn('nrow(results) == 59L', verifier)
            self.assertIn('sum(results$status == "pass") == 59L', verifier)
            self.assertIn('sum(results$status == "expected-exclusion") == 0L', verifier)
            self.assertIn('c(17L, 41L, 1L)', verifier)
            self.assertIn('any(inventory$release != 118L)', verifier)
            self.assertIn('full verification', verifier)
            self.assertNotIn('1823L', verifier)
            self.assertNotIn(str(ORACLE.ROOT), patch)
            ORACLE.verify_staged(work, after)
            (staged / "verify-worker.R").write_text("changed")
            with self.assertRaises(ValueError):
                ORACLE.verify_staged(work, after)

    def test_canonical_gate_remains_unchanged(self):
        verifier = (ORACLE.HERE / "verify.R").read_text()
        common = (ORACLE.HERE / "common.R").read_text()
        self.assertIn('nrow(results) == 1823L', verifier)
        self.assertIn('sum(results$status == "pass") == 1821L', verifier)
        self.assertIn('sum(results$status == "expected-exclusion") == 2L', verifier)
        self.assertIn('roundtrip_corpora <- c("DHS", "MICS", "NSFG")', common)

    def test_installed_inventory_detects_changes_and_rejects_links(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory)
            package = library / "dtatools"
            package.mkdir()
            with self.assertRaises(ValueError):
                ORACLE.package_inventory(library)
            description = package / "DESCRIPTION"
            description.write_text("Package: dtatools\n")
            before = ORACLE.package_inventory(library)
            description.write_text("Package: dtatools\nVersion: 1\n")
            self.assertNotEqual(before, ORACLE.package_inventory(library))
            (package / "linked").symlink_to(description)
            with self.assertRaises(ValueError):
                ORACLE.package_inventory(library)


if __name__ == "__main__":
    unittest.main()

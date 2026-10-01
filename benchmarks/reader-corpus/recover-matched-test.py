import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("recover_matched", Path(__file__).with_name("recover-matched.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MembershipRecovery(unittest.TestCase):
    def inventory(self, sizes=(2, 3, 7)):
        return [dict(corpus="TEST", id=str(i), release="105", bytes=str(size))
                for i, size in enumerate(sizes)]

    def summary(self, count=2, excluded=1, size="0.000000005"):
        return [dict(corpus="TEST", release="105", files=str(count),
                     excluded_files=str(excluded), input_gb=size)]

    def test_unique_membership(self):
        selected, proof = module.reconstruct(self.inventory(), self.summary())
        self.assertEqual(selected, {"0", "1"})
        self.assertEqual(proof[0]["enumerated_subsets"], 3)

    def test_ambiguous_membership_rejected(self):
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            module.reconstruct(self.inventory((2, 3, 3)), self.summary())

    def test_missing_membership_rejected(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            module.reconstruct(self.inventory(), self.summary(size="0.000000006"))

    def test_duplicate_ids_rejected(self):
        rows = self.inventory()
        rows[1]["id"] = rows[0]["id"]
        with self.assertRaisesRegex(ValueError, "duplicate IDs"):
            module.reconstruct(rows, self.summary())

    def test_added_inventory_group_rejected(self):
        rows = self.inventory() + [dict(corpus="OTHER", id="extra", release="105", bytes="1")]
        with self.assertRaisesRegex(ValueError, "format summary"):
            module.reconstruct(rows, self.summary())

    def test_duplicate_summary_rejected(self):
        with self.assertRaisesRegex(ValueError, "format summary"):
            module.reconstruct(self.inventory(), self.summary() * 2)

    def test_count_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, "format count"):
            module.reconstruct(self.inventory(), self.summary(excluded=2))

    def test_fractional_byte_target_rejected(self):
        with self.assertRaisesRegex(ValueError, "exact nonnegative byte"):
            module.reconstruct(self.inventory(), self.summary(size="0.0000000051"))

    def test_original_inventory_digest_required_before_cache_access(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "inventory.tsv"
            path.write_text("unbound inventory\n")
            with self.assertRaisesRegex(ValueError, "historical SHA-256"):
                module.private_membership(path, Path(directory) / "absent", [], set())

    def test_published_inventory_recovers_exact_aggregate(self):
        rows = module.read_table(module.EVIDENCE / "inventory.csv")
        summaries = module.read_table(module.EVIDENCE / "historical-format-summary.tsv", "\t")
        selected, proof = module.reconstruct(rows, summaries)
        self.assertEqual(len(rows), 1823)
        self.assertEqual(len(selected), 1812)
        self.assertTrue(all(p["matching_subsets"] == 1 for p in proof))
        for corpus, expected in module.EXPECTED_TOTALS.items():
            members = [r for r in rows if r["corpus"] == corpus and r["id"] in selected]
            self.assertEqual((len(members), sum(int(r["bytes"]) for r in members)), expected)


if __name__ == "__main__":
    unittest.main()

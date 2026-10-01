"""Keep the installed native-test inventory aligned with package sources."""

import hashlib
import json
from pathlib import Path
import re
import unittest


PACKAGE = Path(__file__).resolve().parents[1] / "r-package" / "dtatools"
MANIFEST = json.loads((PACKAGE / "tools/native-test-manifest.json").read_text(encoding="utf-8"))


class NativeManifestTests(unittest.TestCase):
    def test_exports_match_namespace(self):
        exports = []
        for value in re.findall(r"^export\((.+)\)$", (PACKAGE / "NAMESPACE").read_text(encoding="utf-8"), re.M):
            exports.append(json.loads(value) if value.startswith('"') else value)
        self.assertCountEqual(MANIFEST["exports"], exports)

    def test_every_test_file_is_assigned_once(self):
        actual = [item["path"] for family in MANIFEST["families"] for item in family["files"]]
        expected = [path.relative_to(PACKAGE).as_posix() for path in (PACKAGE / "tests/testthat").glob("test-*.R")]
        self.assertCountEqual(actual, expected)

    def test_tabulate_oracle_fixtures_are_included(self):
        actual = {item["path"] for item in MANIFEST["fixtures"]}
        expected = {path.relative_to(PACKAGE).as_posix() for path in (PACKAGE / "tests/testthat/fixtures").glob("tabulate*")}
        self.assertLessEqual(expected, actual)

    def test_bound_sources_have_current_hashes(self):
        sources = [*MANIFEST["helpers"], *MANIFEST["fixtures"]]
        sources.extend(item for family in MANIFEST["families"] for item in family["files"])
        for item in sources:
            with self.subTest(path=item["path"]):
                self.assertEqual(hashlib.sha256((PACKAGE / item["path"]).read_bytes()).hexdigest(), item["sha256"])


if __name__ == "__main__":
    unittest.main()

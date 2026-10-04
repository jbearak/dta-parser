"""Keep the installed native-test inventory aligned with package sources."""

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest


PACKAGE = Path(__file__).resolve().parents[1] / "r-package" / "dtatools"
MANIFEST = json.loads((PACKAGE / "tools/native-test-manifest.json").read_text(encoding="utf-8"))
RUNNER_SPEC = importlib.util.spec_from_file_location("run_r_native", Path(__file__).with_name("run-r-native.py"))
RUNNER = importlib.util.module_from_spec(RUNNER_SPEC)
RUNNER_SPEC.loader.exec_module(RUNNER)


class NativeManifestTests(unittest.TestCase):
    def test_native_runner_accepts_current_export_manifest(self):
        RUNNER.validate_exports(MANIFEST["exports"])

    def test_native_runner_rejects_missing_or_invalid_export_names(self):
        for exports in (None, [], "summ", {"summ": True}, [""], ["summ", 1]):
            with self.subTest(exports=exports), self.assertRaisesRegex(ValueError, "export-name list"):
                RUNNER.validate_exports(exports)

    def test_native_runner_rejects_duplicate_export_names(self):
        with self.assertRaisesRegex(ValueError, "unique"):
            RUNNER.validate_exports([*MANIFEST["exports"], "summ"])

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

    def test_literal_child_requests_are_declared_in_their_family(self):
        request = re.compile(r"\.dtatools_child_r(_bg)?\(\s*(['\"])([^'\"\n]+)\2")
        for family in MANIFEST["families"]:
            declared = {child["id"]: child["kind"] for child in family["children"]}
            for item in family["files"]:
                for match in request.finditer((PACKAGE / item["path"]).read_text()):
                    kind = "r_bg" if match.group(1) else "r"
                    with self.subTest(family=family["id"], path=item["path"], child=match.group(3)):
                        self.assertEqual(declared.get(match.group(3)), kind,
                                         "Installed runner rejects undeclared child id/kind")

    def test_arithmetic_checkpoint_blocks_allow_only_the_profile_skip(self):
        source = (PACKAGE / "tests/testthat/test-arithmetic-payload-lifetime.R").read_text()
        starts = list(re.finditer(r'^test_that\("([^"\\]*)"', source, re.M))
        blocks = {block["test"]: block for family in MANIFEST["families"]
                  for block in family["blocks"]
                  if block["file"] == "test-arithmetic-payload-lifetime.R"}
        for index, match in enumerate(starts):
            end = starts[index + 1].start() if index + 1 < len(starts) else len(source)
            if ".arithmetic_lifetime_checkpoint_ready()" not in source[match.start():end]:
                continue
            with self.subTest(test=match.group(1)):
                block = blocks[match.group(1)]
                self.assertEqual(block["skip"], "allow")
                self.assertEqual(block["min_pass_before_skip"], 0)
                self.assertEqual(block["skip_message"],
                    "Reason: arithmetic checkpoint requires an admitted native execution profile")
                self.assertGreater(block["min_pass"], 0)
                self.assertEqual(block["warnings"], 0)


if __name__ == "__main__":
    unittest.main()

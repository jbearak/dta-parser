import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

loader = importlib.util.spec_from_file_location("bindings", Path(__file__).with_name("record-builds.py"))
bindings = importlib.util.module_from_spec(loader)
loader.loader.exec_module(bindings)


class BindingsTests(unittest.TestCase):
    def test_digest_ignores_dictionary_insertion_order(self):
        self.assertEqual(bindings.digest_map({"a": "1", "b": "2"}),
                         bindings.digest_map({"b": "2", "a": "1"}))

    def test_relative_names_reject_traversal(self):
        for name in ("/tmp/file", "../file", "R/../file", "R//file", "./file"):
            with self.assertRaises(ValueError):
                bindings.relative_name(name)

    def test_patch_uses_repository_labels_and_exact_text(self):
        patch = bindings.text_patch({"R/x.R": b"old\n"}, {"R/x.R": b"new\n"})
        self.assertEqual(patch, "--- a/r-package/dtatools/R/x.R\n+++ b/r-package/dtatools/R/x.R\n@@ -1 +1 @@\n-old\n+new\n")

    def test_patch_rejects_private_paths_and_binary_changes(self):
        for data in (b"/private/tmp/secret\n", b"/Users/example/input\n", b"\0\n", b"no-final-newline"):
            with self.assertRaises(ValueError):
                bindings.text_patch({"R/x.R": b"old\n"}, {"R/x.R": data})

    def test_compiled_snapshot_requires_every_base_file(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                bindings.source_record(dict(source=directory, native_mode="compiled"), {"src/x.c": b"x\n"})

    def test_reuse_records_native_omissions_but_requires_r_files(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "R").mkdir()
            (source / "R/x.R").write_bytes(b"new\n")
            base = {"R/x.R": b"old\n", "src/x.c": b"native\n"}
            record, _ = bindings.source_record(dict(source=directory, native_mode="reused-baseline"), base)
            self.assertEqual(record["omitted_base_files"], ["src/x.c"])
            self.assertEqual(record["changed_files"], ["R/x.R"])
            (source / "src").mkdir()
            (source / "src/x.c").write_bytes(b"modified\n")
            with self.assertRaises(ValueError):
                bindings.source_record(dict(source=directory, native_mode="reused-baseline"), base)

    def test_unrecorded_compilation_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "src").mkdir()
            (source / "src/injected.c").write_bytes(b"unrecorded\n")
            with self.assertRaises(ValueError):
                bindings.source_record(dict(source=directory, native_mode="compiled"), {})

    def test_inventory_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "dtatools"
            (package / "libs").mkdir(parents=True)
            (package / "libs/dtatools.so").write_bytes(b"DLL")
            (package / "alias").symlink_to("libs/dtatools.so")
            with self.assertRaises(ValueError):
                bindings.installed_inventory(Path(directory))

    def test_capture_matches_baseline_and_source_dll(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = {"R/x.R": b"old\n"}
            for name in ("baseline", "candidate"):
                library = root / name / "dtatools/libs"
                library.mkdir(parents=True)
                (library / "dtatools.so").write_bytes(b"DLL")
            source = root / "source"
            (source / "R").mkdir(parents=True)
            (source / "src").mkdir()
            (source / "R/x.R").write_bytes(b"new\n")
            (source / "src/dtatools.so").write_bytes(b"DLL")
            prior = root / "prior.json"
            prior.write_text(json.dumps({"libraries": {"candidate": {
                "production_source": {"R/x.R": bindings.sha_bytes(base["R/x.R"])},
                "installed_files": bindings.installed_inventory(root / "baseline"),
                "install_log_sha256": "old-build-log"
            }}}))
            log = root / "install.log"
            log.write_bytes(b"build log\n")
            config = dict(baseline=dict(library=str(root / "baseline"), record=str(prior)),
                candidates=[dict(id="test", source=str(source), library=str(root / "candidate"),
                                 build_log=str(log), native_mode="compiled")])
            record, patches = bindings.capture(config, base)
            self.assertTrue(record["baseline"]["base_git_production_verified"])
            self.assertTrue(record["candidates"]["test"]["native"]["source_build_dll_equals_installed"])
            self.assertIn("test.patch", patches)
            config["root"] = directory
            config["candidates"][0]["source_commit"] = "commit"
            with patch.object(bindings, "base_files", return_value=("commit", {"R/x.R": b"new\n"})):
                record, _ = bindings.capture(config, base)
                self.assertEqual(record["candidates"]["test"]["source"]["verified_commit"], "commit")
            with patch.object(bindings, "base_files", return_value=("commit", {"R/x.R": b"wrong\n"})):
                with self.assertRaises(ValueError):
                    bindings.capture(config, base)
            del config["candidates"][0]["source_commit"]
            (source / "src/dtatools.so").write_bytes(b"different DLL")
            with self.assertRaises(ValueError):
                bindings.capture(config, base)
            config["candidates"][0]["native_mode"] = "reused-baseline"
            (source / "inst/libs").mkdir(parents=True)
            (source / "inst/libs/dtatools.so").write_bytes(b"DLL")
            record, _ = bindings.capture(config, base)
            self.assertTrue(record["candidates"]["test"]["native"]["source_reused_dll_equals_installed"])
            (source / "inst/libs/dtatools.so").write_bytes(b"different DLL")
            with self.assertRaises(ValueError):
                bindings.capture(config, base)


if __name__ == "__main__":
    unittest.main()

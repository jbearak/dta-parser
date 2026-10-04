#!/usr/bin/env python3
"""Controller guards with fake libraries and retained CSVs; no R or timing."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("dense_controller", HERE / "dense-run.py")
CONTROLLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTROLLER)
PACKAGE_FILES = ("DESCRIPTION", "NAMESPACE", "R/dtatools.rdb", "R/dtatools.rdx")


class DenseControllerGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def libraries(self, suffix=".so"):
        result = {}
        for role in ("baseline", "candidate"):
            library = self.root / (role + suffix)
            package = library / "dtatools"
            for name in (*PACKAGE_FILES, "libs/arch/dtatools" + suffix):
                path = package / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(role + ":" + name)
            result[role] = library
        return result

    def replay(self, libraries, mutate=None, mutation_call=1):
        output = self.root / "output"
        calls = 0

        def fake_worker(command, **kwargs):
            nonlocal calls
            calls += 1
            role = next(role for role, path in libraries.items()
                        if str(path) == command[2])
            # The retained rows test qualification/receipt control flow only.
            # Their measured times are never presented as a new benchmark.
            shutil.copyfile(HERE / "evidence/final/dense" /
                            f"{role}-round{command[3]}.csv", command[4])
            if mutate is not None and calls == mutation_call:
                mutate()
            return subprocess.CompletedProcess(command, 0)

        argv = ["dense-run.py", "--baseline-library", str(libraries["baseline"]),
                "--candidate-library", str(libraries["candidate"]),
                "--output", str(output)]
        with mock.patch.object(sys, "argv", argv), \
                mock.patch.object(CONTROLLER.subprocess, "run", side_effect=fake_worker) as worker, \
                contextlib.redirect_stdout(io.StringIO()):
            CONTROLLER.main()
        return json.loads((output / "summary.json").read_text()), worker.call_count

    def test_supported_libraries_record_complete_before_after_bindings(self):
        for suffix in (".so", ".dll", ".dylib"):
            with self.subTest(suffix=suffix):
                libraries = self.libraries(suffix)
                summary, calls = self.replay(libraries)
                self.assertEqual(calls, 12)
                self.assertEqual(summary["status"], "PASS")
                self.assertEqual(summary["timed_observations"], 36)
                self.assertEqual(summary["before"]["installed_packages"],
                                 summary["after"]["installed_packages"])
                for role, library in libraries.items():
                    names = {*PACKAGE_FILES, "libs/arch/dtatools" + suffix}
                    binding = summary["after"]["installed_packages"][role]
                    self.assertEqual(set(binding), names)
                    for name in names:
                        self.assertEqual(binding[name], hashlib.sha256(
                            (library / "dtatools" / name).read_bytes()).hexdigest())
                shutil.rmtree(self.root / "output")

    def test_missing_library_is_rejected(self):
        libraries = self.libraries()
        (libraries["baseline"] / "dtatools/libs/arch/dtatools.so").unlink()
        with self.assertRaisesRegex(RuntimeError, "exactly one"):
            CONTROLLER.library_binding(libraries["baseline"])

    def test_symlink_library_binds_resolved_package_files(self):
        libraries = self.libraries()
        alias = self.root / "library-alias"
        alias.symlink_to(libraries["baseline"], target_is_directory=True)
        self.assertEqual(CONTROLLER.library_binding(alias),
                         CONTROLLER.library_binding(libraries["baseline"]))

    def test_ambiguous_library_is_rejected(self):
        libraries = self.libraries()
        (libraries["baseline"] / "dtatools/libs/arch/dtatools.dll").write_bytes(b"extra")
        with self.assertRaisesRegex(RuntimeError, "exactly one"):
            CONTROLLER.library_binding(libraries["baseline"])

    def test_incomplete_installed_package_is_rejected(self):
        libraries = self.libraries()
        for name in PACKAGE_FILES:
            with self.subTest(name=name):
                path = libraries["baseline"] / "dtatools" / name
                original = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(RuntimeError, "incomplete"):
                    CONTROLLER.library_binding(libraries["baseline"])
                path.write_bytes(original)

    def test_drift_in_either_library_aborts_before_publication(self):
        libraries = self.libraries()
        for role in libraries:
            for name in (*PACKAGE_FILES, "libs/arch/dtatools.so"):
                with self.subTest(role=role, name=name):
                    path = libraries[role] / "dtatools" / name
                    original = path.read_bytes()
                    try:
                        with self.assertRaisesRegex(RuntimeError, "installed package changed"):
                            self.replay(libraries, lambda: path.write_bytes(original + b"drift"))
                        self.assertFalse((self.root / "output/summary.json").exists())
                    finally:
                        path.write_bytes(original)
                        shutil.rmtree(self.root / "output", ignore_errors=True)

    def test_last_worker_drift_aborts_before_publication(self):
        libraries = self.libraries()
        path = libraries["baseline"] / "dtatools/R/dtatools.rdb"
        with self.assertRaisesRegex(RuntimeError, "installed package changed"):
            self.replay(libraries, lambda: path.write_bytes(b"late drift"), mutation_call=12)
        self.assertFalse((self.root / "output/summary.json").exists())


if __name__ == "__main__":
    unittest.main()

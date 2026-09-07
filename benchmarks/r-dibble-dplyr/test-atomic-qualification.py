"""Run the real CLI with synthetic external measurements to test evidence guards."""
import csv
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

R_NAMES = ["helpers.R", "owned-double-helpers.R", "owned-atomic-helpers.R",
           "owned-atomic.R", "owned-atomic-memory.R"]
KINDS = ["string", "declared_character", "logical", "factor", "ordered"]
READS = ["any_na", "nonmissing_count", "coercion_character", "export_data_frame",
         "export_tibble", "filter_half", "row_subset", "read_dta", "write_dta", "read_arrow", "write_arrow"]
EXTRA = [["byte_width"], ["byte_width"], ["coercion_integer", "sum", "mean"],
         ["coercion_integer"], ["coercion_integer", "range"]]


def child():
    driver, scenario, *arguments = sys.argv[2:]
    repo, output, library = map(Path, arguments[1:4])
    original_run = subprocess.run

    def measured(command, **kwargs):
        if command[0] == "git":
            return original_run(command, **kwargs)
        if command[0] not in ["Rscript", "/usr/bin/time"]:
            raise RuntimeError(f"Unexpected external command: {command}")
        text = f"source_sha package-source\nlibrary {library.resolve()}\nmode candidate\n"
        text += "\n".join(f"runner_md5 benchmarks/r-dibble-dplyr/{name} " + hashlib.md5(
            (repo / "benchmarks/r-dibble-dplyr" / name).read_bytes()).hexdigest() for name in R_NAMES) + "\n"
        for field in ["runner_md5", "source_sha", "library", "mode"]:
            if scenario == f"runtime_{field}":
                text = text.replace(field, "wrong_field", 1)
        if command[0] == "Rscript":
            (output / "owned-atomic-session.txt").write_text(text)
            tables = {"owned-atomic.csv": [], "owned-atomic-after-read.csv": [], "owned-atomic-writes.csv": []}
            for kind, extra in zip(KINDS, EXTRA):
                for rows in [100000, 1000000]:
                    for family in ["direct", "safe_delegation"]:
                        for operation in ["rename", "select", "relocate", "pipeline_five"]:
                            tables["owned-atomic.csv"].append(dict(kind=kind, family=family, operation=operation, rows=rows))
                    for operation in READS + extra:
                        tables["owned-atomic.csv"].append(dict(kind=kind, family="read", operation=operation, rows=rows))
                        tables["owned-atomic-after-read.csv"].append(dict(kind=kind, after_operation=operation, rows=rows))
                    if kind in KINDS[:3]:
                        for operation in ["shared_sparse", "private_sparse", "full_replacement"]:
                            tables["owned-atomic-writes.csv"].append(dict(kind=kind, operation=operation, rows=rows))
            for name, rows in tables.items():
                if scenario == name:
                    rows.pop()
                if scenario == "duplicate_case" and name == "owned-atomic.csv":
                    rows[-1] = rows[0].copy()
                for row in rows:
                    row.update(r_allocated_bytes=0, r_largest_allocation_bytes=0)
                    if name == "owned-atomic.csv":
                        row.update(median_ms=0, iterations=7)
                if scenario == "allocation":
                    rows[0]["r_allocated_bytes"] = "nan"
                if name == "owned-atomic.csv" and scenario in ["median", "iterations"]:
                    rows[0]["median_ms" if scenario == "median" else "iterations"] = -1
                with (output / name).open("x") as file:
                    writer = csv.DictWriter(file, fieldnames=rows[0])
                    writer.writeheader()
                    writer.writerows(rows)
        else:
            if scenario != "rss":
                text += " 123456 maximum resident set size\n"
            text += "retained_with_source_vector_heap_bytes 12000\n"
            text += "excess_after_drop_result_bytes -100\n"
            if scenario != "heap":
                text += "released_with_last_result_bytes 1.2e+08\n"
            if scenario == "duplicate_metric":
                text += "excess_after_drop_result_bytes -100\n"
        kwargs["stdout"].write(text)
        if scenario in ["final_source", "final_driver"]:
            changed = "helpers.R" if scenario == "final_source" else "run-atomic-qualification.py"
            (repo / "benchmarks/r-dibble-dplyr" / changed).write_text("changed\n")
        return subprocess.CompletedProcess(command, 9 if scenario == "command" else 0)

    sys.argv = [driver, *arguments]
    with patch("subprocess.run", measured):
        runpy.run_path(driver, run_name="__main__")


class AtomicQualificationTests(unittest.TestCase):
    def test_guards(self):
        driver_bytes = Path(__file__).with_name("run-atomic-qualification.py").read_bytes()
        modes = [("default", [], None), ("-O", ["-O"], None), ("PYTHONOPTIMIZE=1", [], "1")]
        cases = ["success", "source", "driver", "command", "runtime_runner_md5", "runtime_source_sha",
                 "runtime_library", "runtime_mode", "owned-atomic.csv", "owned-atomic-after-read.csv",
                 "owned-atomic-writes.csv", "duplicate_case", "allocation", "median", "iterations",
                 "final_source", "final_driver", "existing_output", "manifest_source_sha",
                 "manifest_runner_source_sha", "manifest_library", "manifest_mode", "manifest_runner_sha256",
                 "memory_cases", "existing_memory_log", "changed_evidence", "rss", "heap", "duplicate_metric"]
        for mode, flags, optimize in modes:
            for case in cases:
                with self.subTest(mode=mode, case=case), tempfile.TemporaryDirectory() as temp:
                    root = Path(temp)
                    repo = root / "repo"
                    runner_dir = repo / "benchmarks/r-dibble-dplyr"
                    runner_dir.mkdir(parents=True)
                    for name in R_NAMES:
                        (runner_dir / name).write_text(f"# Synthetic {name}\n")
                    driver = runner_dir / "run-atomic-qualification.py"
                    driver.write_bytes(driver_bytes)

                    def git(*args):
                        return subprocess.check_output(["git", *args], cwd=repo, stderr=subprocess.STDOUT).decode().strip()

                    git("init", "-q")
                    git("add", ".")
                    git("-c", "user.name=Qualification test", "-c", "user.email=qualification@example.invalid",
                        "commit", "-qm", "fixture")
                    sha = git("rev-parse", "HEAD")
                    output, library = root / "output", root / "library"
                    env = os.environ.copy()
                    env.pop("PYTHONOPTIMIZE", None)
                    env["PYTHONDONTWRITEBYTECODE"] = "1"
                    if optimize:
                        env["PYTHONOPTIMIZE"] = optimize

                    def execute(kind, scenario):
                        return subprocess.run([sys.executable, *flags, str(Path(__file__).resolve()), "--child",
                            str(driver), scenario, kind, str(repo), str(output), str(library), "package-source", sha,
                            "candidate"], env=env, text=True, capture_output=True)

                    memory = case.startswith("manifest_") or case in ["success", "memory_cases",
                        "existing_memory_log", "changed_evidence", "rss", "heap", "duplicate_metric"]
                    if memory:
                        result = execute("operations", "success")
                        self.assertEqual(result.returncode, 0, result.stderr)
                        manifest_path = output / "root-manifest.json"
                        manifest = json.loads(manifest_path.read_text())
                        if case.startswith("manifest_"):
                            manifest[case.removeprefix("manifest_")] = "wrong"
                        if case == "memory_cases":
                            manifest["memory_cases"] = ["existing"]
                        manifest_path.write_text(json.dumps(manifest))
                        if case == "existing_memory_log":
                            (output / "memory-ordered-pipeline_50-1000000.log").write_text("preserve this log\n")
                        if case == "changed_evidence":
                            (output / "owned-atomic.csv").write_text("preserve altered evidence\n")
                    if case in ["source", "driver"]:
                        # The driver mismatch retains valid executable bytes.
                        path = runner_dir / ("helpers.R" if case == "source" else "run-atomic-qualification.py")
                        path.write_bytes(path.read_bytes() + b"\n# changed\n")
                    if case == "existing_output":
                        output.mkdir()
                        (output / "sentinel").write_text("preserve output\n")
                    before = {p.name: p.read_bytes() for p in output.glob("*")} if output.exists() else {}
                    result = execute("memory" if memory else "operations", case)
                    if case == "success":
                        self.assertEqual(result.returncode, 0, result.stderr)
                        final = json.loads((output / "root-manifest.json").read_text())
                        self.assertEqual(len(final["memory_cases"]), 30)
                        self.assertEqual(final["csv_rows"], {"owned-atomic.csv": 206,
                            "owned-atomic-after-read.csv": 126, "owned-atomic-writes.csv": 18})
                    else:
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertIn("RuntimeError:", result.stderr)
                        if case in ["source", "driver"]:
                            self.assertFalse(output.exists())
                        for name, content in before.items():
                            self.assertEqual((output / name).read_bytes(), content, name)
                        if not memory:
                            self.assertFalse((output / "root-manifest.json").exists())
                        if case == "existing_memory_log":
                            self.assertFalse((output / "memory-string-rename-100000.log").exists())
                    print(f"PASS {mode}: {case}", flush=True)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child":
        child()
    else:
        unittest.main()

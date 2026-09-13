"""Reader-driver regression tests; no R reader, private input or benchmark runs."""
import copy
import csv
import contextlib
import io
import itertools
import json
import os
from pathlib import Path
import subprocess
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import driver_common as common

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]


def job(key, code=0):
    """Make a minimal qualification record accepted by the real command audit."""
    return dict(key=key, exit_code=code,
                command=["/test/Rscript", "--vanilla", str(BASE / "compare.R"), "input.dta", "input.arrow"])


def worker_text(case, elapsed=.125):
    """Emit the actual warm worker's paired clock and dimension marker format."""
    count, rows, columns = common.WARM_CASES[case]
    return "\n".join(f"iteration\t{i}\t{elapsed}\t{rows}\t{columns}\ncpu\t{i}\t.25\t.125"
                     for i in range(1, count + 1)) + "\n"


class DriverTests(unittest.TestCase):
    """Exercise recorded attempts, completed cohorts and public parsing boundaries."""

    def setUp(self):
        """Create an isolated directory holding only synthetic text records."""
        self.temporary = tempfile.TemporaryDirectory(prefix="reader-driver-tests-")
        self.directory = Path(self.temporary.name)
        self.attempts = {}

    def tearDown(self):
        """Remove the test's disposable records."""
        self.temporary.cleanup()

    def append_warm(self, planned, position, code=0, elapsed=.125):
        """Record an immutable fake worker log with its actual attempt position."""
        key = planned["key"]
        self.attempts[key] = self.attempts.get(key, 0) + 1
        filename = f"{key}.attempt-{self.attempts[key]:04d}.log"
        log = self.directory / filename
        log.write_text(worker_text(planned["case"], elapsed))
        command = ["/test/Rscript", "--vanilla", str(BASE / "workers/arrow.R")]
        if planned["method"] == "read_dta":
            command += ["read-dta", "input.dta", str(planned["iterations"])]
        else:
            command += ["read-arrow", "input.arrow", str(planned["iterations"]),
                        "verify" if planned["method"] == "read_arrow_verify" else "noverify"]
        return dict(key=key, exit_code=code, command=command, log_file=filename,
                    log_sha256=common.sha(log), warm=dict(planned, execution_position=position))

    def cohort(self, failed_qualification=False):
        """Create complete balanced text observations after all qualifications."""
        schedule = common.warm_read_schedule()
        jobs = [job("compare-india", 1)] if failed_qualification else []
        jobs += [job("compare-" + case) for case in common.WARM_CASES]
        jobs += [self.append_warm(row, i) for i, row in enumerate(schedule, 1)]
        return dict(warm_schedule=schedule), jobs

    def test_positions_and_every_pairwise_order_are_balanced_for_each_case(self):
        schedule = common.warm_read_schedule()
        self.assertEqual(len(schedule), 54)
        self.assertEqual(sum(row["iterations"] for row in schedule), 486)
        self.assertEqual(len({row["key"] for row in schedule}), 54)
        self.assertEqual([row["scheduled_position"] for row in schedule], list(range(1, 55)))
        for case in common.WARM_CASES:
            orders = [[row["method"] for row in schedule if row["case"] == case and row["cohort"] == cohort]
                      for cohort in range(1, 7)]
            self.assertEqual({tuple(order) for order in orders}, set(itertools.permutations(common.WARM_METHODS)))
            for method in common.WARM_METHODS:
                self.assertEqual([sum(order.index(method) == position for order in orders)
                                  for position in range(3)], [2, 2, 2])
            for first, second in itertools.combinations(common.WARM_METHODS, 2):
                self.assertEqual(sum(order.index(first) < order.index(second) for order in orders), 3)
            positions = [row["case_position"] for row in schedule if row["case"] == case and row["method_position"] == 1]
            self.assertEqual([positions.count(i) for i in range(1, 4)], [2, 2, 2])

    def test_failure_then_success_keeps_history_and_selects_final_attempt(self):
        jobs = [job("compare-india", 1), job("compare-india", 0)]
        original = copy.deepcopy(jobs)
        self.assertIs(common.latest_job_attempts(jobs)["compare-india"], jobs[-1])
        self.assertEqual(jobs, original)

    def test_success_then_final_failure_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "latest job attempts failed"):
            common.latest_job_attempts([job("compare-india"), job("compare-india", 1)])

    def test_missing_or_unexpected_final_keys_are_rejected(self):
        for keys in [set(), {"compare-india", "compare-1gb"}]:
            with self.subTest(keys=keys), self.assertRaisesRegex(ValueError, "job keys differ"):
                common.latest_job_attempts([job("compare-india")], keys)

    def test_malformed_job_records_are_rejected(self):
        path = self.directory / "jobs.jsonl"
        values = ["{", "", "[]", json.dumps(dict(job("x"), exit_code=True)),
                  json.dumps(dict(job("x"), exit_code=-256)), json.dumps(dict(job("x"), command="Rscript")),
                  json.dumps(dict(job("x"), log_file="../other.log")), json.dumps(job("../x"))]
        for value in values:
            with self.subTest(value=value):
                path.write_text(value + "\n")
                with self.assertRaises(ValueError):
                    common.load_jobs(path)

    def test_signaled_attempt_is_retained_before_success(self):
        path = self.directory / "jobs.jsonl"
        path.write_text("".join(json.dumps(row) + "\n" for row in [job("x", -9), job("x")]))
        attempts = common.load_jobs(path)
        self.assertEqual([row["exit_code"] for row in attempts], [-9, 0])
        self.assertEqual(common.latest_job_attempts(attempts)["x"]["exit_code"], 0)

    def test_disallowed_worker_or_comparator_command_is_rejected(self):
        command = ["/test/Rscript", "--vanilla", str(BASE / "workers/corpus.R"), "haven", "input.dta"]
        with self.assertRaises(ValueError):
            common.validate_read_commands([dict(job("x"), command=command)], ROOT)
        with self.assertRaises(ValueError):
            common.validate_read_commands([dict(job("x"), command=["stata", "--vanilla", "file.do"])], ROOT)

    def test_warm_parser_preserves_order_fields_and_matches_cpu_by_iteration(self):
        planned = common.warm_read_schedule()[0]
        text = "\n".join(reversed(worker_text(planned["case"]).splitlines()))
        rows = common.parse_warm_output(text, planned, 91)
        self.assertEqual(len(rows), 11)
        self.assertEqual([r["iteration"] for r in rows], list(range(1, 12)))
        for row in rows:
            self.assertEqual((row["cohort"], row["case_position"], row["method_position"], row["execution_position"]), (1, 1, 1, 91))
            self.assertEqual((row["elapsed_seconds"], row["cpu_seconds"]), (.125, .375))

    def test_warm_parser_rejects_missing_duplicate_nonfinite_negative_and_wrong_dimensions(self):
        planned = common.warm_read_schedule()[0]
        text = worker_text(planned["case"])
        bad = [text.replace("cpu\t11\t.25\t.125\n", ""), text + "cpu\t1\t.25\t.125\n",
               text + "iteration\t1\t.125\t231956\t40\n", text.replace("0.125", "nan", 1),
               text.replace("0.125", "inf", 1), text.replace("cpu\t1\t.25", "cpu\t1\t-1", 1),
               text.replace("231956", "231955", 1), text.replace("iteration\t1\t", "iteration\t0\t", 1),
               text.replace("cpu\t1\t.25\t.125", "cpu\t1\t.25", 1)]
        for value in bad:
            with self.subTest(value=value[:50]), self.assertRaises(ValueError):
                common.parse_warm_output(value, planned, 1)

    def test_complete_cohort_recovers_from_failed_qualification(self):
        binding, jobs = self.cohort(failed_qualification=True)
        rows = common.collect_warm_observations(self.directory, binding, jobs)
        self.assertEqual(len(rows), 486)
        self.assertEqual({r["execution_position"] for r in rows}, set(range(1, 55)))

    def test_retry_uses_final_attempt_logs_and_actual_execution_positions(self):
        schedule = common.warm_read_schedule()
        jobs = [job("compare-" + case) for case in common.WARM_CASES]
        jobs += [self.append_warm(schedule[0], 1), self.append_warm(schedule[1], 2, code=1)]
        jobs += [job("compare-" + case) for case in common.WARM_CASES]
        jobs += [self.append_warm(row, i + 2, elapsed=.5) for i, row in enumerate(schedule, 1)]
        rows = common.collect_warm_observations(self.directory, dict(warm_schedule=schedule), jobs)
        self.assertEqual(rows[0]["execution_position"], 3)
        self.assertTrue(all(row["elapsed_seconds"] == .5 for row in rows))

    def test_unqualified_or_changed_order_or_changed_method_is_rejected(self):
        binding, original = self.cohort()
        broken = []
        broken.append(original[1:])
        jobs = copy.deepcopy(original);jobs[3]["warm"]["execution_position"] = 2;broken.append(jobs)
        jobs = copy.deepcopy(original);jobs[3]["command"][3] = "read-arrow";broken.append(jobs)
        jobs = copy.deepcopy(original);jobs[3]["command"][5] = "10";broken.append(jobs)
        broken.append(original[:-1])
        for jobs in broken:
            with self.subTest(), self.assertRaises(ValueError):
                common.collect_warm_observations(self.directory, binding, jobs)

    def test_changed_log_or_schedule_is_rejected(self):
        binding, jobs = self.cohort()
        changed = copy.deepcopy(binding);changed["warm_schedule"][0]["method_position"] = 2
        with self.assertRaises(ValueError):common.collect_warm_observations(self.directory, changed, jobs)
        (self.directory / jobs[3]["log_file"]).write_text("altered")
        with self.assertRaisesRegex(ValueError, "log changed"):
            common.collect_warm_observations(self.directory, binding, jobs)

    def test_runner_preserves_failed_and_successful_attempt_logs(self):
        real_spawn = os.posix_spawn
        commands = iter(["printf failed; exit 1", "printf succeeded; exit 0"])
        def spawn(_binary, _arguments, environment, file_actions):
            return real_spawn("/bin/sh", ["sh", "-c", next(commands)], environment, file_actions=file_actions)
        with patch.object(common.shutil, "which", return_value="/test/Rscript"), patch.object(common.os, "posix_spawn", side_effect=spawn):
            with self.assertRaises(RuntimeError):
                common.run_child(self.directory, "compare-india", BASE / "compare.R", ["a", "b"], os.environ.copy())
            common.run_child(self.directory, "compare-india", BASE / "compare.R", ["a", "b"], os.environ.copy())
        jobs = common.load_jobs(self.directory / "jobs.jsonl")
        self.assertEqual([j["exit_code"] for j in jobs], [1, 0])
        self.assertEqual([(self.directory / j["log_file"]).read_text() for j in jobs], ["failed", "succeeded"])
        self.assertEqual((self.directory / "compare-india.log").read_text(), "succeeded")
        self.assertEqual(common.latest_job_attempts(jobs)["compare-india"]["attempt"], 2)

    def test_untracked_package_source_is_rejected_before_installation_lookup(self):
        with patch.object(common.subprocess, "run"), patch.object(common.subprocess, "check_output", return_value="r-package/dtatools/src/new.rs\n"):
            with self.assertRaisesRegex(RuntimeError, "untracked package source"):
                common.source_binding(self.directory, self.directory, self.directory / "absent.json", [])

    def test_cpu_validation_rejects_malformed_markers(self):
        self.assertEqual(common.read_cpu("DTATOOLS_CPU\t.25\t.125\n")["cpu_seconds"], .375)
        for text in ("", "DTATOOLS_CPU\t1\n", "DTATOOLS_CPU\t1\t2\t3\n",
                     "DTATOOLS_CPU\t1\t2\nDTATOOLS_CPU\t1\t2\n",
                     *(f"DTATOOLS_CPU\t{value}\t1\n" for value in ("x", "-1", "nan", "inf")),
                     "DTATOOLS_CPU\t1e308\t1e308\n"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                common.read_cpu(text)

    def test_source_and_installation_guards_remain_mandatory(self):
        with self.assertRaises(RuntimeError):
            common.require(False)
        package = self.directory / "dtatools"
        package.mkdir()
        for path in (self.directory / "absent", package):
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                common.tree_sha(path)
        contents = package / "DESCRIPTION"
        contents.write_text("Package: dtatools\n")
        alias = self.directory / "alias"
        alias.symlink_to(package, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            common.tree_sha(alias)
        link = package / "linked"
        link.symlink_to(contents)
        with self.assertRaises(RuntimeError):
            common.tree_sha(package)
        link.unlink()
        installed = common.tree_sha(package)
        record = self.directory / "build.json"
        for record_tree, source_tree, recorded_files, message in (
                ("other", "tree", installed, "build package tree differs"),
                ("tree", "other", installed, "build source commit package tree differs"),
                ("tree", "tree", {}, "complete installed package")):
            record.write_text(json.dumps(dict(package_tree=record_tree, source_commit="build", installed=recorded_files)))
            with self.subTest(message=message), patch.object(common.subprocess, "run"), \
                    patch.object(common.subprocess, "check_output", side_effect=["", "head", "tree", source_tree]):
                with self.assertRaisesRegex(RuntimeError, message):
                    common.source_binding(self.directory, self.directory, record, [])

    def test_optimized_python_preserves_validation_boundaries(self):
        """Exercise real optimized imports and the CLI without invoking R."""
        selected = ("test_untracked_package_source_is_rejected_before_installation_lookup",
                    "test_cpu_validation_rejects_malformed_markers",
                    "test_source_and_installation_guards_remain_mandatory",
                    "test_warm_only_cli_publishes_recovered_cohort_and_rejects_final_failure")
        result = subprocess.run([sys.executable, "-O", str(Path(__file__).resolve()),
                                 *("DriverTests." + name for name in selected)],
                                text=True, capture_output=True,
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONOPTIMIZE="1"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_warm_only_cli_publishes_recovered_cohort_and_rejects_final_failure(self):
        binding, jobs = self.cohort(failed_qualification=True)
        for key in ["spot-india", "spot-nsfg", "spot-india-arrow"]:
            jobs.append(job(key))
        for case in ["tall", "wide", "tall-wide", "india-2021-wm"]:
            jobs.append(dict(job("projection-" + case), command=["/test/Rscript", "--vanilla", str(BASE / "workers/projection.R"), "input", "present", "union", "11", "output"]))
        (self.directory / "jobs.jsonl").write_text("".join(json.dumps(j) + "\n" for j in jobs))
        (self.directory / "binding.json").write_text(json.dumps(dict(binding, scripts={})))
        (self.directory / "COMPLETE").write_text("complete\n")
        (self.directory / "read-inputs.tsv").write_text("case\tdta_sha256\n100mb\tfixture-hash\n")
        output = self.directory / "public"
        command = [sys.executable, str(BASE / "summarize.py"), "unused-corpus", str(self.directory), str(output), "--data-root", str(self.directory), "--warm-only"]
        result = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        self.assertEqual(result.returncode, 0, result.stderr)
        with (output / "warm-read-observations.csv").open() as stream:self.assertEqual(len(list(csv.DictReader(stream))), 486)
        provenance = json.loads((output / "warm-provenance.json").read_text())
        self.assertEqual(provenance["historical_failed_qualification_attempts"], 1)
        self.assertEqual({r["path"] for r in provenance["published_csvs"]},
                         {"warm-read-observations.csv", "warm-read-summary.csv", "warm-cohort-summary.csv", "read-inputs.csv"})
        for artifact in provenance["published_csvs"]:
            path = output / artifact["path"]
            self.assertEqual(artifact["path_base"], "public output directory")
            self.assertEqual(artifact["bytes"], path.stat().st_size)
            self.assertEqual(artifact["sha256"], common.sha(path))
        with (self.directory / "jobs.jsonl").open("a") as stream:stream.write(json.dumps(job("compare-india", 1)) + "\n")
        command[4] = str(self.directory / "rejected")
        result = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list((self.directory / "rejected").glob("*.csv")))

    def test_reads_driver_qualifies_every_pair_then_executes_its_bound_schedule(self):
        """Run the real Python entry point with inert files and mocked reader children."""
        data, cache, output = [self.directory / name for name in ("data", "cache", "output")]

        def file(path, text="fixture"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            return path

        def table(path, rows):
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("w") as stream:
                writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter="\t")
                writer.writeheader();writer.writerows(rows)

        inventory = []
        for key, corpus in [("DHS-0259", "DHS"), ("NSFG-0206", "NSFG")]:
            path = file(cache / (key + ".dta"))
            inventory.append(dict(corpus=corpus, id=key, relative_path=path.name,
                                  bytes=path.stat().st_size, mtime=path.stat().st_mtime))
        archive = data / "r-corpus-performance/20260824T142432Z"
        table(archive / "inventory.tsv", inventory)
        table(archive / "raw.tsv", [dict(id=row["id"], reader="dtaparser") for row in inventory])
        table(data / "r-corpus-performance/20260824T201626Z/inventory.tsv",
              [dict(row, release=119) for row in inventory])
        datasets = []
        for name in ("100mb", "1gb"):
            path = file(data / (name + ".dta"))
            datasets.append(dict(dataset=name, path=str(path), sha256=common.sha(path)))
            file(data / ("arrow-interchange/synthetic-" + name + ".arrow"))
        table(data / "large-scale/datasets.tsv", datasets)
        file(data / "arrow-interchange/india-2021-wm.arrow")
        for run, names in [("run-full-20260828T202309Z", ["tall", "wide", "tall-wide"]),
                           ("run-india-20260828T203157Z", ["india-2021-wm"])]:
            directory = data / "projection-introspection" / run
            file(directory / "summary.tsv", "case\tmethod\n")
            for name in names:
                file(directory / name / "input.dta")
                names_dir = directory / name if name == "india-2021-wm" else directory
                file(names_dir / "present.txt", "a b")
                file(names_dir / "union.txt", "a b absent")
        jobs = []

        def child(directory, key, script, arguments, environment, warm=None):
            record = dict(key=key, exit_code=0, command=["/test/Rscript", "--vanilla", str(script), *map(str, arguments)])
            text = worker_text(warm["case"]) if warm else "qualified\n"
            if warm is not None:record["warm"] = dict(warm)
            jobs.append(record)
            (directory / (key + ".log")).write_text(text)
            with (directory / "jobs.jsonl").open("a") as stream:stream.write(json.dumps(record) + "\n")
            return record, text

        binding = dict(commit="test-commit", source_tree="test-tree", installed={}, scripts={})
        arguments = [str(BASE / "refresh.py"), str(self.directory / "library"), str(output),
                     "--phase", "reads", "--data-root", str(data), "--cache", str(cache),
                     "--build-record", str(self.directory / "build.json")]
        previous = Path.cwd()
        try:
            with patch.object(sys, "argv", arguments), patch.object(common, "run_child", side_effect=child), \
                 patch.object(common, "source_binding", return_value=binding), \
                 patch.object(common.subprocess, "run"), patch.object(common.subprocess, "check_output", return_value="test-commit\n"), \
                 contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(BASE / "refresh.py"), run_name="__main__")
        finally:
            os.chdir(previous)
        self.assertEqual([j["key"] for j in jobs[:3]], ["compare-100mb", "compare-1gb", "compare-india"])
        warm_jobs = [j for j in jobs if "warm" in j]
        self.assertEqual(len(warm_jobs), 54)
        self.assertEqual(jobs[3:57], warm_jobs)
        recorded_binding = json.loads((output / "binding.json").read_text())
        self.assertEqual(recorded_binding["warm_schedule"], common.warm_read_schedule())
        self.assertEqual(len(common.collect_warm_observations(output, recorded_binding, jobs)), 486)
        self.assertTrue((output / "COMPLETE").exists())


if __name__ == "__main__":
    unittest.main()

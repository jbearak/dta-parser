#!/usr/bin/env python3
"""Test retained security evidence without executing CodeQL or a native build."""
import importlib.util
import json
from pathlib import Path
import shlex
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_collector", HERE / "collector.py")
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)
STAMP = "[2026-10-04 15:48:03]"


class NativeSecurityEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dtatools-codeql-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.db = self.root / "production-codeql-db"
        self.log = self.db / "cpp/log"
        self.log.mkdir(parents=True)
        self.names = json.loads((HERE / "expected-query-names.json").read_text())
        self.assertEqual(len(self.names), 61)
        self.assertEqual(len(set(self.names)), 61)
        self.queries = {}
        self.result_paths = {}
        for name in self.names:
            relative = name.removeprefix("codeql/cpp-queries/")
            source = self.root / "official/qlpacks/codeql/cpp-queries/1.9.0" / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("synthetic source for " + name)
            source.with_suffix(".qlx").write_bytes(("synthetic compiled " + name).encode())
            self.queries[name] = {
                "source": str(source),
                "sha256": collector.sha(source),
                "compiled_sha256": collector.sha(source.with_suffix(".qlx")),
            }
            result = (self.db / "cpp/results" / name).with_suffix(".bqrs")
            result.parent.mkdir(parents=True, exist_ok=True)
            result.write_bytes(("synthetic result " + name).encode())
            self.result_paths[name] = result
        self.run = self.log / "database-run-queries-test.log"
        self.execute = self.log / "execute-queries-test.log"
        self.interpret = self.log / "database-interpret-results-test.log"
        self.run.write_text(self.command_line([
            "database", "run-queries", "--ram=14575", "--threads=4",
            str(self.db / "cpp"), "--min-disk-free=1024", "--max-disk-cache=32768",
        ]) + STAMP + " Exiting with code 70\n")
        self.execute_command = self.command_line([
            "execute", "queries", "--threads=4", "--max-disk-cache=32768",
            "--output=" + str(self.db / "cpp/results"), "--",
            str(self.db / "cpp/db-cpp"), "path:" + str(self.db / "cpp/temp/config-queries.qls"),
        ])
        self.progress = {
            name: STAMP + " [PROGRESS] execute queries> Evaluation done; writing results to "
            + str(Path(name).with_suffix(".bqrs")) + ".\n"
            for name in self.names
        }
        self.write_execute()
        self.interpret_command = self.command_line([
            "database", "interpret-results", "--threads=4", "--format=sarif-latest",
            "--output=../results/cpp.sarif", "--print-diagnostics-summary",
            "--sarif-category", "/language:c-cpp", "--sarif-include-diagnostics",
            str(self.db / "cpp"),
        ])
        self.found = [
            STAMP + " [DETAILS] database interpret-results>  ... found results file at "
            + str(self.result_paths[name]) + ".\n"
            for name in self.names
        ]
        kinds = ("pathproblem", "problem", "metric")
        self.interpreted = [
            STAMP + ' [DETAILS] database interpret-results> Interpreted '
            + kinds[index % len(kinds)] + ' query "Fixture query" (cpp/fixture) at path '
            + str(self.result_paths[name]) + ".\n"
            for index, name in enumerate(self.names)
        ]
        self.write_interpret()

    @staticmethod
    def command_line(argv):
        return STAMP + " This is codeql " + shlex.join(argv) + "\n"

    def write_execute(self, omitted=()):
        self.execute.write_text(self.execute_command + "".join(
            self.progress[name] for name in self.names if name not in omitted
        ) + STAMP + " Exiting with code 0\n")

    def write_interpret(self, found=None, interpreted=None):
        self.interpret.write_text(
            self.interpret_command + "".join(self.found if found is None else found)
            + "".join(self.interpreted if interpreted is None else interpreted)
            + STAMP + " Terminating normally.\n"
        )

    def command_check(self):
        return collector.security_command_binding(self.db, self.queries, self.log)

    def binding_check(self):
        return collector.security_binding(self.db, {"queries": self.queries})

    def replace(self, path, before, after):
        text = path.read_text()
        self.assertIn(before, text)
        path.write_text(text.replace(before, after, 1))

    def assert_ledger_rejected(self, mutate):
        for ledger in ("found", "interpreted"):
            with self.subTest(ledger=ledger):
                rows = list(getattr(self, ledger))
                mutate(rows)
                self.write_interpret(**{ledger: rows})
                with self.assertRaisesRegex(ValueError, "interpreted security result ledger"):
                    self.command_check()
        self.write_interpret()

    def test_full_security_binding(self):
        result = self.binding_check()
        self.assertEqual(result["queries"], 61)
        self.assertEqual(len(result["results"]), 61)
        self.assertEqual(result["interpreted_queries"], sorted(self.names))
        self.assertEqual(result["progress_completion_count"], 61)

    def test_lost_completion_notification_for_any_query_is_accepted(self):
        for name in self.names:
            with self.subTest(omitted=name):
                self.write_execute(omitted=(name,))
                result = self.command_check()
                self.assertEqual(result["queries"], 61)
                self.assertEqual(result["progress_completion_count"], 60)
                self.assertEqual(result["progress_missing_queries"], [name])
        self.assertEqual(len(self.binding_check()["results"]), 61)

    def test_progress_notifications_are_not_completion_evidence(self):
        self.write_execute(omitted=self.names)
        result = self.binding_check()
        self.assertEqual(result["queries"], 61)
        self.assertEqual(result["progress_completion_count"], 0)
        self.assertEqual(result["progress_missing_queries"], sorted(self.names))

    def test_missing_result_record_is_rejected_in_both_ledgers(self):
        self.assert_ledger_rejected(lambda rows: rows.pop())

    def test_duplicate_result_record_is_rejected_in_both_ledgers(self):
        self.assert_ledger_rejected(lambda rows: rows.append(rows[0]))

    def test_duplicate_replacing_another_result_is_rejected(self):
        def duplicate(rows):
            rows[0] = rows[1]
        self.assert_ledger_rejected(duplicate)

    def test_foreign_result_path_is_rejected_in_both_ledgers(self):
        def foreign(rows):
            rows[0] = rows[0].replace(str(self.result_paths[self.names[0]]),
                                    str(self.db / "cpp/results/codeql/cpp-queries/Foreign.bqrs"))
        self.assert_ledger_rejected(foreign)

    def test_wrong_database_result_path_is_rejected_in_both_ledgers(self):
        def other_database(rows):
            rows[0] = rows[0].replace(str(self.db), str(self.root / "other-db"))
        self.assert_ledger_rejected(other_database)

    def test_missing_interpretation_command_is_rejected(self):
        self.interpret.unlink()
        with self.assertRaisesRegex(ValueError, "security interpretation command"):
            self.command_check()

    def test_repeated_interpretation_command_is_rejected(self):
        (self.log / "database-interpret-results-other.log").write_bytes(self.interpret.read_bytes())
        with self.assertRaisesRegex(ValueError, "security interpretation command"):
            self.command_check()

    def test_wrong_interpreter_database_is_rejected(self):
        self.replace(self.interpret, str(self.db / "cpp") + "\n",
                     str(self.root / "other-db/cpp") + "\n")
        with self.assertRaisesRegex(ValueError, "different security database"):
            self.command_check()

    def test_wrong_sarif_category_is_rejected(self):
        self.replace(self.interpret, "/language:c-cpp", "/language:python")
        with self.assertRaisesRegex(ValueError, "interpretation category"):
            self.command_check()

    def test_missing_sarif_category_is_rejected(self):
        self.replace(self.interpret, "--sarif-category /language:c-cpp ", "")
        with self.assertRaisesRegex(ValueError, "interpretation category"):
            self.command_check()

    def test_duplicate_sarif_category_is_rejected(self):
        self.replace(self.interpret, "--sarif-category /language:c-cpp",
                     "--sarif-category /language:c-cpp --sarif-category /language:python")
        with self.assertRaisesRegex(ValueError, "interpretation category"):
            self.command_check()

    def test_non_sarif_interpretation_is_rejected(self):
        self.replace(self.interpret, "--format=sarif-latest", "--format=csv")
        with self.assertRaisesRegex(ValueError, "not interpreted as SARIF"):
            self.command_check()

    def test_abnormal_interpreter_termination_is_rejected(self):
        self.replace(self.interpret, "Terminating normally.", "Exiting with code 99")
        with self.assertRaisesRegex(ValueError, "did not terminate normally"):
            self.command_check()

    def test_interpretation_log_after_normal_termination_is_rejected(self):
        with self.interpret.open("a") as output:
            output.write(STAMP + " Unexpected trailing command.\n")
        with self.assertRaisesRegex(ValueError, "did not terminate normally"):
            self.command_check()

    def test_duplicate_normal_termination_is_rejected(self):
        with self.interpret.open("a") as output:
            output.write(STAMP + " Terminating normally.\n")
        with self.assertRaisesRegex(ValueError, "did not terminate normally"):
            self.command_check()

    def test_missing_cache_cap_is_rejected_in_both_commands(self):
        for path in (self.run, self.execute):
            with self.subTest(command=path.name):
                original = path.read_text()
                self.replace(path, " --max-disk-cache=32768", "")
                with self.assertRaisesRegex(ValueError, "cache cap not applied exactly"):
                    self.command_check()
                path.write_text(original)

    def test_wrong_cache_cap_is_rejected(self):
        self.replace(self.run, "--max-disk-cache=32768", "--max-disk-cache=65536")
        with self.assertRaisesRegex(ValueError, "cache cap not applied exactly"):
            self.command_check()

    def test_duplicate_cache_cap_is_rejected(self):
        self.replace(self.execute, "--max-disk-cache=32768",
                     "--max-disk-cache=32768 --max-disk-cache=32768")
        with self.assertRaisesRegex(ValueError, "cache cap not applied exactly"):
            self.command_check()

    def test_failed_evaluator_is_rejected(self):
        self.replace(self.execute, "Exiting with code 0", "Exiting with code 99")
        with self.assertRaisesRegex(ValueError, "evaluator did not exit successfully"):
            self.command_check()

    def test_unexpected_security_suite_is_rejected(self):
        self.replace(self.execute, "config-queries.qls", "partial-suite.qls")
        with self.assertRaisesRegex(ValueError, "Unexpected evaluated security suite"):
            self.command_check()

    def test_repeated_full_evaluator_is_rejected(self):
        (self.log / "execute-queries-other.log").write_bytes(self.execute.read_bytes())
        with self.assertRaisesRegex(ValueError, "full security evaluator command"):
            self.command_check()

    def test_helper_evaluator_is_distinct_from_security_evaluator(self):
        (self.log / "execute-queries-helper.log").write_text(self.command_line([
            "execute", "queries", "--max-disk-cache=1024",
            "--output=" + str(self.root / "coverage/helper.bqrs"),
            "--", str(self.db / "cpp/db-cpp"), "path:helper.ql",
        ]))
        self.assertEqual(self.command_check()["queries"], 61)

    def test_partial_bqrs_inventory_is_rejected(self):
        self.result_paths[self.names[0]].unlink()
        with self.assertRaisesRegex(ValueError, "Incomplete default security query results"):
            self.binding_check()

    def test_foreign_bqrs_output_is_rejected(self):
        (self.db / "cpp/results/codeql/cpp-queries/Foreign.bqrs").write_bytes(b"foreign")
        with self.assertRaisesRegex(ValueError, "Unknown security result"):
            self.binding_check()

    def test_duplicate_bqrs_output_is_rejected(self):
        duplicate = (self.db / "copy/results" / self.names[0]).with_suffix(".bqrs")
        duplicate.parent.mkdir(parents=True)
        duplicate.write_bytes(self.result_paths[self.names[0]].read_bytes())
        with self.assertRaisesRegex(ValueError, "Duplicate security result"):
            self.binding_check()

    def test_changed_query_source_is_rejected(self):
        Path(self.queries[self.names[0]]["source"]).write_text("changed source")
        with self.assertRaisesRegex(ValueError, "Official query changed"):
            self.binding_check()

    def test_changed_compiled_query_is_rejected(self):
        Path(self.queries[self.names[0]]["source"]).with_suffix(".qlx").write_bytes(b"changed compiled query")
        with self.assertRaisesRegex(ValueError, "Official query changed"):
            self.binding_check()


if __name__ == "__main__":
    unittest.main()

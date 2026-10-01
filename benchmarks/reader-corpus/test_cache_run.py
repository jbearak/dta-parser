"""Coverage, qualification, condition, and measurement checks without private data or R."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("cache_run", Path(__file__).with_name("cache-run.py"))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def record(identifier, output, status="ok"):
    value = dict(id=identifier, output=output, status=status,
        conditions=dict(warnings=[], error_class=[], error_message=[]), conditions_sha256="a" * 64)
    if status == "ok":
        value.update(rows=12, columns=3, signature="complete-signature")
    else:
        value["conditions"].update(error_class=["simpleError", "error", "condition"], error_message="bad file")
    return value


class InventoryTests(unittest.TestCase):
    def test_partial_cache_cannot_satisfy_requested_inventory(self):
        RUN.validate_inventory_count([{}, {}], 2)
        for actual, expected in (([{}], 2), ([{}, {}, {}], 2), ([], 0)):
            with self.subTest(actual=actual, expected=expected), self.assertRaises(RuntimeError):
                RUN.validate_inventory_count(actual, expected)

    def test_all_corpora_and_case_suffixes_but_no_symlink_aliases(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for corpus in ("DHS", "MICS", "NSFG", "ENADID", "WFS", "CFR"):
                directory = root / corpus
                directory.mkdir()
                (directory / "data.DTA").write_bytes(b"\x71fixture")
                (directory / "ignored.csv").write_text("x\n")
            (root / "MICS/empty.dta").write_bytes(b"")
            (root / "MICS/alias").symlink_to(root / "DHS", target_is_directory=True)
            (root / "MICS/linked.dta").symlink_to(root / "DHS/data.DTA")
            observed = RUN.inventory(root)
            self.assertEqual(len(observed["files"]), 7)
            self.assertEqual(len(observed["skipped_symlinks"]), 2)
            self.assertEqual(len({row["id"] for row in observed["files"]}), 7)
            self.assertEqual(sum(row["bytes"] == 0 for row in observed["files"]), 1)

    def test_exclusion_requires_stable_id_corpus_bytes_and_hash(self):
        digest = "a" * 64
        row = dict(corpus="MICS", relative_path="MICS/example.dta", bytes=17)
        canonical = "MICS-" + hashlib.sha256("\x1f".join((row["corpus"], row["relative_path"], digest)).encode()).hexdigest()[:24]
        expected = {canonical: dict(corpus="MICS", bytes=17, sha256=digest, reason="malformed-source")}
        with patch.object(RUN, "KNOWN_EXCLUSIONS", expected):
            self.assertEqual(RUN.expected_exclusion(row, dict(sha256=digest))["canonical_id"], canonical)
            self.assertIsNone(RUN.expected_exclusion(dict(row, bytes=18), dict(sha256=digest)))
            self.assertIsNone(RUN.expected_exclusion(dict(row, relative_path="MICS/other.dta"), dict(sha256=digest)))
            self.assertIsNone(RUN.expected_exclusion(row, dict(sha256="b" * 64)))

    def test_canonical_exclusion_constants_match_retained_oracle_contract(self):
        canonical = (RUN.HERE.parent / "r-corpus-roundtrip/common.R").read_text()
        self.assertEqual(len(RUN.KNOWN_EXCLUSIONS), 2)
        for identifier, value in RUN.KNOWN_EXCLUSIONS.items():
            self.assertIn(identifier, canonical)
            self.assertIn(value["sha256"], canonical)
            self.assertIn(value["reason"], canonical)


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.files = [dict(id="readable"), dict(id="malformed")]
        self.records = {(row["id"], output): record(row["id"], output,
            "dta_error" if row["id"] == "malformed" else "ok")
            for row in self.files for output in RUN.OUTPUTS}

    def test_complete_parity_including_known_error(self):
        RUN.validate_qualification(self.files, self.records, self.records, {"malformed"})

    def test_shared_unexpected_failure_is_not_waived(self):
        with self.assertRaisesRegex(RuntimeError, "Unexpected DTA failure"):
            RUN.validate_qualification(self.files, self.records, self.records, set())

    def test_metadata_warning_and_error_class_changes_fail(self):
        for identifier, field, value in (("readable", "signature", "changed"),
                ("readable", "columns", 4), ("readable", "conditions", dict(warnings=["new warning"])),
                ("malformed", "conditions", dict(error_class=["otherError"], error_message="bad file", warnings=[]))):
            candidate = copy.deepcopy(self.records)
            candidate[(identifier, "tibble")][field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                RUN.validate_qualification(self.files, self.records, candidate, {"malformed"})

    def test_missing_container_is_rejected(self):
        incomplete = dict(self.records)
        del incomplete[("readable", "tibble")]
        with self.assertRaisesRegex(RuntimeError, "Incomplete"):
            RUN.validate_qualification(self.files, self.records, incomplete, {"malformed"})

    def test_existing_container_signature_difference_is_recorded(self):
        records = copy.deepcopy(self.records)
        records[("readable", "dibble")]["signature"] = "normalized-string-storage"
        differences = RUN.validate_qualification(self.files, records, records, {"malformed"})
        self.assertEqual(differences, [dict(id="readable", tibble_signature="complete-signature",
            dibble_signature="normalized-string-storage")])
        candidate = copy.deepcopy(records)
        candidate[("readable", "dibble")]["signature"] = "candidate-regression"
        with self.assertRaisesRegex(RuntimeError, "within output"):
            RUN.validate_qualification(self.files, records, candidate, {"malformed"})

    def test_shared_cross_output_shape_and_condition_differences_fail(self):
        for field, value in (("columns", 4), ("conditions_sha256", "b" * 64),
                ("conditions", dict(warnings=["container-specific warning"]))):
            records = copy.deepcopy(self.records)
            records[("readable", "dibble")][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "across outputs"):
                RUN.validate_qualification(self.files, records, records, {"malformed"})


class RevalidationTests(unittest.TestCase):
    def test_only_controller_may_change_and_original_must_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            archived = Path(temporary) / "original.py"
            archived.write_bytes(b"original controller\n")
            original = dict(workers={RUN.CONTROLLER: RUN.sha(archived), "worker.R": "worker-hash"},
                inputs={"input": "input-hash"}, builds={"candidate": "bound-library"}, runtime="R-runtime")
            current = copy.deepcopy(original)
            current["workers"][RUN.CONTROLLER] = "corrected-controller"
            RUN.validate_revalidation_bindings(original, current, archived)
            for section, key in (("workers", "worker.R"), ("inputs", "input"), ("builds", "candidate")):
                changed = copy.deepcopy(current)
                changed[section][key] = "changed"
                with self.subTest(section=section), self.assertRaisesRegex(RuntimeError, "beyond"):
                    RUN.validate_revalidation_bindings(original, changed, archived)
            changed = dict(current, runtime="different-R")
            with self.assertRaisesRegex(RuntimeError, "beyond"):
                RUN.validate_revalidation_bindings(original, changed, archived)
            archived.write_bytes(b"changed original\n")
            with self.assertRaisesRegex(RuntimeError, "Archived original"):
                RUN.validate_revalidation_bindings(original, current, archived)

    def test_sealed_timed_and_incomplete_sources_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            with self.assertRaisesRegex(RuntimeError, "Incomplete"):
                RUN.revalidation_source(source)
            for name in RUN.SOURCE_ARTIFACTS:
                (source / name).write_text("fixture\n")
            RUN.revalidation_source(source)
            for name in ("QUALIFIED", "MEASUREMENT_STARTED", "COMPLETE", "observations.jsonl"):
                (source / name).touch()
                with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, "without timing"):
                    RUN.revalidation_source(source)
                (source / name).unlink()

    def test_complete_records_are_copied_unchanged_into_a_new_bound_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, output = root / "source", root / "revalidated"
            source.mkdir()
            archived = root / "original.py"
            archived.write_bytes(b"original controller\n")
            files = [dict(id="readable"), dict(id="error-one"), dict(id="error-two")]
            full_inventory = dict(files=files)
            original = dict(workers={RUN.CONTROLLER: RUN.sha(archived), "worker.R": "worker-hash"},
                inputs={row["id"]: dict(bytes=1, sha256="a"*64) for row in files})
            current = copy.deepcopy(original)
            current["workers"][RUN.CONTROLLER] = "corrected-controller"
            RUN.write_json(source / "config-private.json", dict(expected_files=3, smoke=False, cache=str(root)))
            RUN.write_json(source / "inventory-private.json", full_inventory)
            RUN.write_json(source / "inputs-private.json", files)
            RUN.write_json(source / "binding-before.json", original)
            records = [record(row["id"], output, "ok" if row["id"] == "readable" else "dta_error")
                       for row in files for output in RUN.OUTPUTS]
            records[1]["signature"] = "normalized-string-storage"
            raw = "".join(json.dumps(row) + "\n" for row in records)
            for variant in ("baseline", "candidate"):
                (source / (variant + "-qualification-private.jsonl")).write_text(raw)
            source_hashes = RUN.revalidation_source(source)
            args = SimpleNamespace(source_output=source, output=output, original_controller=archived)
            def exclusion(row, _identity):
                return dict(reason="fixture", canonical_id=row["id"]) if row["id"].startswith("error-") else None
            with patch.object(RUN, "inventory", return_value=full_inventory), \
                 patch.object(RUN, "bindings", return_value=current), \
                 patch.object(RUN, "expected_exclusion", side_effect=exclusion):
                RUN.revalidate(args)
            self.assertEqual(RUN.revalidation_source(source), source_hashes)
            for variant in ("baseline", "candidate"):
                name = variant + "-qualification-private.jsonl"
                self.assertEqual((source / name).read_bytes(), (output / name).read_bytes())
            audit = json.loads((output / "revalidation.json").read_text())
            self.assertEqual(audit["original_artifact_sha256"], source_hashes)
            self.assertEqual(audit["new_r_qualification_reads"], 0)
            self.assertEqual(len(json.loads((output / "qualification.json").read_text())[
                "cross_output_signature_differences"]), 1)
            seal = json.loads((output / "QUALIFIED").read_text())
            self.assertEqual(RUN.qualified_seal(output), seal)
            (output / "original-controller.py").write_bytes(b"modified\n")
            self.assertNotEqual(RUN.qualified_seal(output), seal)
            (source / "candidate-qualification-private.jsonl").write_text(
                "".join(json.dumps(row) + "\n" for row in records[:-1]))
            incomplete_output = root / "incomplete-must-not-exist"
            args.output = incomplete_output
            with patch.object(RUN, "inventory", return_value=full_inventory), \
                 patch.object(RUN, "bindings", return_value=current), \
                 patch.object(RUN, "expected_exclusion", side_effect=exclusion), \
                 self.assertRaisesRegex(RuntimeError, "Incomplete"):
                RUN.revalidate(args)
            self.assertFalse(incomplete_output.exists())


class TimingTests(unittest.TestCase):
    def test_condition_identity_required_and_duplicate_rejected(self):
        q = record("readable", "tibble")
        marker = "DTATOOLS_BENCH\tok\t0.012\t12\t3\nDTATOOLS_CPU\t0.020\t0.002\n"
        conditions = "DTATOOLS_CONDITIONS\t" + "a" * 64 + "\n"
        result = RUN.parse_timed(marker + conditions, q)
        self.assertAlmostEqual(result["read_cpu_seconds"], 0.022)
        for corrupt in (marker, marker + conditions * 2, marker + conditions.replace("a", "b")):
            with self.subTest(corrupt=corrupt), self.assertRaises(RuntimeError):
                RUN.parse_timed(corrupt, q)

    def test_attempt_completeness_includes_malformed_and_both_containers(self):
        files = [dict(id="readable"), dict(id="malformed")]
        rows = [dict(id=row["id"], output=output) for row in files for output in RUN.OUTPUTS]
        RUN.validate_observations(rows, files)
        for corrupt in (rows[:-1], rows + rows[:1], rows[:-1] + rows[:1]):
            with self.subTest(corrupt=corrupt), self.assertRaises(RuntimeError):
                RUN.validate_observations(corrupt, files)


if __name__ == "__main__":
    unittest.main()

import importlib.util
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import run

# Avoid Python's standard-library module named profile.
spec = importlib.util.spec_from_file_location("reader_profile", HERE / "profile.py")
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class HarnessTests(unittest.TestCase):
    def test_pairwise_order_balance(self):
        schedules = run.orders()
        self.assertEqual(len(schedules), 10)
        for schedule in schedules:
            self.assertCountEqual(schedule, run.SETTINGS)
        for first in run.SETTINGS:
            for second in run.SETTINGS:
                if first != second:
                    self.assertEqual(sum(row.index(first) < row.index(second)
                                         for row in schedules), 5)
        for index in range(0, 10, 2):
            self.assertEqual(schedules[index], tuple(reversed(schedules[index + 1])))

    def test_stata_timed_interval(self):
        script = run.stata_program(Path("/plugin/cpuclock.plugin"),
            Path("/private/input data.dta"), Path("/private/result.csv"), 8, 7, 3)
        interval = script.split("plugin call cpuclock, start\n")[1].split(
            "plugin call cpuclock, stop\n")[0]
        self.assertEqual(interval, 'quietly use "/private/input data.dta", clear\n')
        self.assertIn("assert c(processors) == 8", script)
        for clock in ("wall", "user", "system"):
            self.assertIn("scalar(_dta_cpu_" + clock + ")", script)
        self.assertNotIn("timer ", script)

    def test_empty_interval_has_no_read(self):
        script = run.stata_program(Path("/plugin"), Path("/input"), Path("/output"),
            1, 7, 3, empty=True)
        self.assertIn("plugin call cpuclock, start\nplugin call cpuclock, stop", script)
        self.assertNotIn("quietly use", script)

    def test_path_injection_rejected(self):
        for path in ("a\nb", 'a"b', "a$b", "a`b"):
            with self.assertRaises(ValueError):
                run.stata_string(path)

    def test_private_outputs_cannot_nest(self):
        self.assertTrue(run.overlapping_paths(Path("/output"), Path("/output/private")))
        self.assertTrue(run.overlapping_paths(Path("/work/public"), Path("/work")))
        self.assertFalse(run.overlapping_paths(Path("/output"), Path("/private/work")))

    def test_profile_keeps_only_sanitized_leaf_section(self):
        counts, rejected = profile.leaf_counts("""Header /private/path
Call graph:
  900 ignored_parent (in R)
Sort by top of stack, same collapsed (when >= 5):
  12 memcpy (in libsystem_platform.dylib) + 20 [0xabc]
  5 memcpy (in libsystem_platform.dylib) + 28 [0xdef]
  7 /private/user/value (in R)
  3 ??? [0x123]
Binary Images:
  900 forbidden_image
""")
        self.assertEqual(counts, {"memcpy": 17})
        self.assertEqual(rejected, 10)

    def test_qualification_binds_build_and_input(self):
        binding = dict(installed={"libs/dtatools.so": "dll"},
            source=dict(commit="commit", files={"src/reader.c": "source"}),
            inputs={kind: dict(sha256=kind, bytes=10) for kind in ("dta", "arrow")})
        reference = dict(candidate_head="commit", libraries=dict(candidate=dict(
            source_build_dll_equals_installed=True, installed_files=binding["installed"],
            production_source=binding["source"]["files"], install_log_sha256="log")),
            inputs={"case-" + kind: dict(value, rows=7, columns=3)
                    for kind, value in binding["inputs"].items()})
        records = [dict(key="case-" + reader, library="candidate",
            records=["\t".join(("QUALIFIED", reader, "7", "3", "signature"))])
            for reader in ("read_dta", "read_arrow")]
        value = run.qualify_binding(binding, reference, records, "case", 7, 3)
        self.assertEqual(value["signature"], "signature")
        changed = dict(binding, installed={"libs/dtatools.so": "different"})
        with self.assertRaises(ValueError):
            run.qualify_binding(changed, reference, records, "case", 7, 3)
        changed = dict(binding, inputs=dict(binding["inputs"], dta=dict(sha256="other", bytes=10)))
        with self.assertRaises(ValueError):
            run.qualify_binding(changed, reference, records, "case", 7, 3)


if __name__ == "__main__":
    unittest.main()

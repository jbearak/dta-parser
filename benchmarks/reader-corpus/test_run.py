"""Reject incomplete or misleading observations from the corpus worker."""
import unittest

from run import parse_read


class ReadObservationTests(unittest.TestCase):
    def test_success_for_both_readers(self):
        log = "DTATOOLS_BENCH\tok\t0.012\t12\t3\nDTATOOLS_CPU\t0.020\t0.002\n"
        for method in ("read_dta", "read_arrow"):
            result = parse_read(log, method, dict(status="ok", rows=12, columns=3))
            self.assertEqual((result["status"], result["rows"], result["columns"]),
                             ("ok", 12, 3))
            self.assertEqual(result["elapsed_seconds"], 0.012)
            self.assertAlmostEqual(result["read_cpu_seconds"], 0.022)

    def test_only_expected_dta_errors_are_accepted(self):
        log = "DTATOOLS_BENCH\terror\t0.001\tNA\tNA\nDTATOOLS_CPU\t0.001\t0\n"
        self.assertEqual(parse_read(log, "read_dta", dict(status="dta_error"))["status"],
                         "dta_error")
        for method, qualification in [
            ("read_arrow", dict(status="dta_error")),
            ("read_dta", dict(status="ok", rows=12, columns=3)),
        ]:
            with self.subTest(method=method, qualification=qualification):
                with self.assertRaises(RuntimeError):
                    parse_read(log, method, qualification)

    def test_rejects_bad_markers_dimensions_and_clocks(self):
        marker = "DTATOOLS_BENCH\tok\t0.012\t12\t3\n"
        cpu = "DTATOOLS_CPU\t0.020\t0.002\n"
        bad = [cpu, marker, marker + marker + cpu, marker + cpu + cpu,
               marker.replace("\t12\t", "\t13\t") + cpu,
               marker.replace("\t3\n", "\t4\n") + cpu,
               marker.replace("0.012", "nan") + cpu,
               marker.replace("0.012", "-1") + cpu,
               marker + cpu.replace("0.020", "inf"),
               marker + cpu.replace("0.020", "-1"),
               marker.replace("\tok\t", "\tunknown\t") + cpu]
        for log in bad:
            with self.subTest(log=log):
                with self.assertRaises((RuntimeError, ValueError)):
                    parse_read(log, "read_dta", dict(status="ok", rows=12, columns=3))


if __name__ == "__main__":
    unittest.main()

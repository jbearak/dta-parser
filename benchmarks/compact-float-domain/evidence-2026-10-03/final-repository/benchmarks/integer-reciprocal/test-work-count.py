#!/usr/bin/env python3
"""A reduced or corrupted structural probe must fail its completion gate."""
import csv
import importlib.util
import io
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('work_count', Path(__file__).with_name('work-count.py'))
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


def encode(cases):
    stream = io.StringIO()
    writer = csv.writer(stream)
    writer.writerow(('length', 'kind', 'pattern', 'scalar', 'legacy', 'chunk'))
    writer.writerows(cases)
    return stream.getvalue()


class MatrixGuard(unittest.TestCase):
    def test_complete_matrix_and_corruptions(self):
        cases = list(PROBE.expected_cases().elements())
        self.assertEqual(len(cases), 64)
        PROBE.validate_case_matrix(encode(cases))
        wrong_sign = [(*row[:3], '0x0p+0', *row[4:]) if row[3] == (-0.0).hex() else row for row in cases]
        for broken in (cases[:-1], cases + [cases[0]], cases[:-1] + [cases[0]], wrong_sign):
            with self.assertRaisesRegex(RuntimeError, '64-case'):
                PROBE.validate_case_matrix(encode(broken))


if __name__ == '__main__':
    unittest.main()

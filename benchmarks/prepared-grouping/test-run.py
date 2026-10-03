import importlib.util
import itertools
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('grouping_run', Path(__file__).with_name('run.py'))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def observations():
    rows = []
    for case in sorted(RUN.EXPECTED):
        row = dict(zip(RUN.FIELDS, case))
        size = int(row['n']) * int(row['key_count'])
        row.update(round='1', phase='timing', iterations='2', cpu_seconds='.15', elapsed_seconds='.16',
                   scalar_values='0', prepared_values=str(size), prepared_bytes=str(8 * size),
                   key_cache_bytes=str(8 * size), result_sha256='values', metadata_sha256='metadata',
                   result_storage='', source_sha256='source', ranks_sha256='ranks', source_state_sha256='state')
        row['order'] = str(('compact', 'typed_double', 'ordinary').index(row['representation']) + 1)
        rows.append(row)
    return rows


class ProtocolTests(unittest.TestCase):
    def test_complete_matrix(self):
        rows = observations()
        self.assertEqual(len(rows), 60)
        RUN.validate_round(rows, 1, 'candidate')

    def test_r_scientific_notation_preserves_exact_byte_counts(self):
        rows = observations()
        for row in rows:
            row['key_cache_bytes'] = format(float(row['key_cache_bytes']), '.12e')
        RUN.validate_round(rows, 1, 'candidate')

    def test_integer_parser_rejects_inexact_and_nonfinite_values(self):
        for text in ('800000.00000000000000000001', '-1', '-0.1', 'NaN',
                     'Infinity', '-Infinity', '1e1000000', 'not a number'):
            with self.assertRaises(RuntimeError):
                RUN.exact_nonnegative_integer(text)
        self.assertEqual(RUN.exact_nonnegative_integer('8e+05'), 800000)

    def test_missing_and_duplicate_cases_are_rejected(self):
        rows = observations()
        for broken in (rows[:-1], rows[:-1] + [rows[0]]):
            with self.assertRaises(RuntimeError):
                RUN.validate_round(broken, 1, 'candidate')

    def test_invalid_interval_and_qualification_are_rejected(self):
        for field, value in (('cpu_seconds', 'nan'), ('elapsed_seconds', '0'),
                             ('phase', 'qualification'), ('iterations', '0'), ('round', '2')):
            rows = observations()
            rows[0][field] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'candidate')

    def test_unprepared_candidate_is_rejected(self):
        for field in ('prepared_values', 'prepared_bytes', 'key_cache_bytes'):
            rows = observations()
            rows[0][field] = '0'
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'candidate')

    def test_duplicate_positions_are_rejected(self):
        rows = observations()
        for row in rows:
            row['order'] = '1'
        with self.assertRaises(RuntimeError):
            RUN.validate_round(rows, 1, 'candidate')

    def test_balance_checks_all_six_permutations(self):
        rows = []
        for variant in ('baseline', 'candidate'):
            for round_number, order in enumerate(itertools.permutations(
                    ('compact', 'typed_double', 'ordinary')), 1):
                for row in observations():
                    row.update(variant=variant, round=str(round_number),
                               order=str(order.index(row['representation']) + 1))
                    rows.append(row)
        RUN.validate_balance(rows, 6)
        rows[0]['order'] = '9'
        with self.assertRaises(RuntimeError):
            RUN.validate_balance(rows, 6)

    def test_result_or_source_drift_is_rejected(self):
        for field in ('result_sha256', 'metadata_sha256', 'result_storage',
                      'source_sha256', 'ranks_sha256', 'source_state_sha256'):
            rows = observations()
            duplicate = dict(rows[0])
            duplicate[field] = 'changed'
            with self.assertRaises(RuntimeError):
                RUN.validate_results(rows + [duplicate])


if __name__ == '__main__':
    unittest.main()

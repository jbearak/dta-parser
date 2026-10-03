import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('nullable_diagnostic', Path(__file__).with_name('run.py'))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def observation(case, phase='measure'):
    row = {key: case[key] for key in RUN.KEYS}
    row.update(phase=phase, rows='250000', columns='4',
        expected_na_per_column='1' if row['id'].endswith('-one') else
            '251' if row['id'].endswith('-sparse') else '0',
        dictionary_columns_after_workflow='0', values_exact='TRUE', metadata_exact='TRUE',
        raw_encoding_exact='TRUE', consumption_exact='TRUE')
    row.update({key: 'a' * 64 for key in RUN.HASHES})
    row.update({key: '0' for key in RUN.TIMES})
    if phase == 'measure':
        row.update(read_cpu_seconds='.1', read_wall_seconds='.1', total_cpu_seconds='.1',
                   total_wall_seconds='.1')
        if row['mode'] == 'full':
            row.update(consume_cpu_seconds='.02', consume_wall_seconds='.02',
                       total_cpu_seconds='.12', total_wall_seconds='.12',
                       second_cpu_seconds='.01', second_wall_seconds='.01')
    return row


def complete():
    rows = []
    for round_number in range(1, 7):
        for case in RUN.schedule(round_number):
            for variant in ('baseline', 'candidate'):
                rows.append(dict(round=round_number, variant=variant,
                    null_position=case['null_position'], **observation(case)))
    return rows


class DiagnosticGates(unittest.TestCase):
    def test_complete_six_permutations(self):
        rows = complete()
        RUN.validate_results(rows, 6, ('baseline', 'candidate'), 'measure')
        for row in rows:
            RUN.validate_row(row, row, 'measure')

    def test_rejects_missing_and_duplicated_cases(self):
        rows = complete()
        for changed in (rows[:-1], rows[:-1] + [rows[0]]):
            with self.assertRaises(RuntimeError):
                RUN.validate_results(changed, 6, ('baseline', 'candidate'), 'measure')

    def test_rejects_changed_full_result_hash(self):
        for key in RUN.HASHES:
            rows = complete()
            rows[-1][key] = 'b' * 64
            with self.assertRaises(RuntimeError):
                RUN.validate_results(rows, 6, ('baseline', 'candidate'), 'measure')

    def test_rejects_nan_negative_and_zero_read_timing(self):
        case = next(RUN.schedule(1))
        for value in ('nan', '-1', '0'):
            row = observation(case)
            row['read_cpu_seconds'] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_row(row, case, 'measure')

    def test_rejects_gc_and_workflow_accounting_errors(self):
        case = next(RUN.schedule(1))
        for metric, value in (('gc_cpu_seconds', '.2'), ('total_cpu_seconds', '.2')):
            row = observation(case)
            row[metric] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_row(row, case, 'measure')

    def test_requires_original_encoding_oracle(self):
        case = next(RUN.schedule(1))
        row = observation(case)
        row['raw_encoding_exact'] = 'FALSE'
        with self.assertRaises(RuntimeError):
            RUN.validate_row(row, case, 'measure')

    def test_qualification_has_no_clock_observations(self):
        case = next(RUN.schedule(1))
        row = observation(case, 'qualify')
        RUN.validate_row(row, case, 'qualify')
        row['read_cpu_seconds'] = '.1'
        with self.assertRaises(RuntimeError):
            RUN.validate_row(row, case, 'qualify')

    def test_requires_all_permutations_beyond_balanced_positions(self):
        rows = complete()
        cycle = (('zero', 'one', 'sparse'), ('one', 'sparse', 'zero'), ('sparse', 'zero', 'one'))
        for row in rows:
            if row['id'] != 'finite':
                row['null_position'] = cycle[(row['round'] - 1) % 3].index(row['id'].split('-')[1]) + 1
        with self.assertRaises(RuntimeError):
            RUN.validate_results(rows, 6, ('baseline', 'candidate'), 'measure')


if __name__ == '__main__':
    unittest.main()

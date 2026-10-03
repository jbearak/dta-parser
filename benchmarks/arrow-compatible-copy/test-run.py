import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('compatible_run', Path(__file__).with_name('run.py'))
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)


def observations(phase='measure'):
    result = []
    for number in range(1, 7) if phase == 'measure' else (1,):
        for ordinal, case in enumerate(run.schedule(number), 1):
            for variant in run.variants(number, ordinal):
                fixture, threads, mode = case
                missing = 28 if fixture in run.TARGETS[:2] else 32 if fixture in (
                    'nullable_f64', 'nullable_i32', 'compact_i16') else 0
                row = dict(round=str(number), ordinal=str(ordinal), variant=variant,
                    id=fixture, threads=threads, mode=mode, phase=phase, rows='2000000', columns='8',
                    expected_na_per_column=str(missing), route=run.ROUTES[fixture],
                    profile=str(fixture != 'semantic_f64').upper(),
                    retained=str(fixture == 'compact_i16').upper(),
                    compact_columns='8' if fixture == 'compact_i16' else '0',
                    retained_columns='8' if fixture == 'compact_i16' else '0',
                    chunks_per_column='31' if fixture == 'compact_i16' else '0')
                for key in run.HASHES:
                    row[key] = 'a' * 64
                for metric in run.TIMES:
                    row[metric] = '0'
                if phase == 'measure':
                    for unit in ('cpu', 'wall'):
                        row[f'read_{unit}_seconds'] = '.1'
                        row[f'consume_{unit}_seconds'] = '.05' if mode == 'full' else '0'
                        row[f'total_{unit}_seconds'] = '.15' if mode == 'full' else '.1'
                    row['gc_cpu_seconds'] = '.01'
                result.append(row)
    return result


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.rows = observations()

    def reject(self, rows):
        with self.assertRaises(RuntimeError):
            run.validate_all(rows, 6, 'measure')

    def test_complete_matrix_and_summaries(self):
        run.validate_all(self.rows, 6, 'measure')
        self.assertEqual(len(self.rows), 336)
        summary = run.summarize(self.rows)
        self.assertEqual(len(summary), 28)
        self.assertTrue(all(row['read_cpu_seconds_speedup'] == 1 for row in summary))

    def test_no_clock_qualification(self):
        rows = observations('qualify')
        run.validate_all(rows, 1, 'qualify')
        self.assertEqual(len(rows), 56)
        rows[0]['read_cpu_seconds'] = '.1'
        with self.assertRaises(RuntimeError):
            run.validate_all(rows, 1, 'qualify')

    def test_missing_duplicate_and_extra(self):
        self.reject(self.rows[:-1])
        self.reject(self.rows + [self.rows[0]])
        rows = copy.deepcopy(self.rows)
        rows[0] = rows[1]
        self.reject(rows)

    def test_order(self):
        rows = copy.deepcopy(self.rows)
        rows[0], rows[1] = rows[1], rows[0]
        self.reject(rows)
        rows = copy.deepcopy(self.rows)
        rows[0]['ordinal'] = '2'
        self.reject(rows)

    def test_nonfinite_negative_and_zero_read(self):
        for value in ('nan', 'inf', '-1', '0'):
            rows = copy.deepcopy(self.rows)
            rows[0]['read_cpu_seconds'] = value
            self.reject(rows)

    def test_total_gc_and_consumer(self):
        for key, value in (('total_cpu_seconds', '.8'), ('gc_cpu_seconds', '.2'),
                           ('consume_cpu_seconds', '.1')):
            rows = copy.deepcopy(self.rows)
            rows[0][key] = value
            self.reject(rows)
        rows = copy.deepcopy(self.rows)
        next(row for row in rows if row['mode'] == 'full')['consume_wall_seconds'] = '0'
        self.reject(rows)

    def test_hash_and_state(self):
        for key, value in (('values_sha256', 'b' * 64), ('metadata_sha256', 'bad'),
                           ('retained', 'TRUE'), ('profile', 'FALSE')):
            rows = copy.deepcopy(self.rows)
            rows[0][key] = value
            self.reject(rows)

    def test_dimensions_route_and_missing(self):
        for key, value in (('rows', '1999999'), ('columns', '7'),
                           ('expected_na_per_column', '27'), ('route', 'Integer')):
            rows = copy.deepcopy(self.rows)
            rows[0][key] = value
            self.reject(rows)

    def test_native_ownership_is_distinct_from_compact_state(self):
        rows = copy.deepcopy(self.rows)
        next(row for row in rows if row['id'] == 'compact_i16')['retained_columns'] = '0'
        self.reject(rows)
        rows = copy.deepcopy(self.rows)
        next(row for row in rows if row['id'] == 'compact_i16')['chunks_per_column'] = '30'
        self.reject(rows)

    def test_exact_integer_parsing(self):
        self.assertEqual(run.integer('2e6'), 2000000)
        for value in ('NaN', 'Infinity', '2.1'):
            with self.assertRaises(RuntimeError):
                run.integer(value)

    def test_each_case_has_balanced_build_positions(self):
        for case in run.CASES:
            first = []
            for number in range(1, 7):
                ordinal = run.schedule(number).index(case) + 1
                first.append(run.variants(number, ordinal)[0])
            self.assertEqual(first.count('baseline'), 3)
            self.assertEqual(first.count('candidate'), 3)

    def test_worker_csv_identity_and_inventory(self):
        rows = observations('qualify')
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for row in rows:
                worker = {key: value for key, value in row.items()
                          if key not in ('round', 'ordinal', 'variant')}
                run.write_csv(directory / run.worker_name(row), [worker])
            run.validate_workers(directory, rows)
            first = directory / run.worker_name(rows[0])
            worker = run.read_csv(first)
            worker[0]['values_sha256'] = 'b' * 64
            run.write_csv(first, worker)
            with self.assertRaises(RuntimeError):
                run.validate_workers(directory, rows)
            worker[0]['values_sha256'] = 'a' * 64
            run.write_csv(first, worker)
            run.write_csv(directory / 'extra.csv', worker)
            with self.assertRaises(RuntimeError):
                run.validate_workers(directory, rows)


if __name__ == '__main__':
    unittest.main()

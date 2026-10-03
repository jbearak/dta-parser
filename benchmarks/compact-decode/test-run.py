"""Reject incomplete, misqualified, or inconsistent decode evidence."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('decode_controller', Path(__file__).with_name('run.py'))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def observations(round_number=1):
    result = []
    for n, width, backing, density in sorted(RUN.EXPECTED):
        value_hash = hashlib.sha256((width + '/' + density).encode()).hexdigest()
        order = RUN.PERMUTATIONS[(round_number - 1) % 6].index(density) + 1
        backings = ('constructed', 'retained') if round_number % 2 else ('retained', 'constructed')
        row = dict(n=n, width=width, backing=backing, density=density, round=str(round_number),
            phase='timing', sharing='aliased', order=str(order), backing_order=str(backings.index(backing) + 1),
            missing_count=str(RUN.MISSING_COUNTS[density]), batch_size='32', batches='2', iterations='64',
            cpu_seconds='.16', elapsed_seconds='.17', gc_cpu_seconds='.002',
            min_batch_cpu_seconds='.08', max_batch_cpu_seconds='.08',
            min_batch_elapsed_seconds='.085', max_batch_elapsed_seconds='.085',
            zero_cpu_batches='0', zero_wall_batches='0', compact_payload_bytes=str(int(n) * RUN.WIDTHS[width]),
            double_payload_bytes=str(int(n) * 8), compact_copy_bytes='0', compatibility_bytes='0',
            timed_compact_copy_bytes='0', r_profiled_allocation_bytes='8000128',
            r_largest_allocation_bytes='8000048', r_profiled_allocations='3', peak_vcell_bytes='8000032',
            live_vcell_delta_bytes='8000000', source_sha256=value_hash, result_sha256=value_hash,
            alias_independent='TRUE', source_unmaterialized_before='TRUE', source_unmaterialized_after='TRUE',
            targets_unmaterialized_before='TRUE', targets_materialized_after='TRUE',
            retained_chunks=str(RUN.math.ceil(int(n) / 8191) if backing == 'retained' else 0))
        result.append(row)
    return result


def intervals(rows):
    result = []
    for row in rows:
        for batch in (1, 2):
            result.append(dict({key: row[key] for key in RUN.FIELDS}, round=row['round'],
                sharing='aliased', handles='32', batch=str(batch), cpu_seconds='.08',
                elapsed_seconds='.085', gc_cpu_seconds='.001', compact_copy_bytes='0'))
    return result


class ControllerTests(unittest.TestCase):
    def test_complete_round_and_balanced_aggregate(self):
        combined = []
        for number in range(1, 7):
            rows = observations(number)
            RUN.validate_round(rows, number, 'timing')
            RUN.validate_intervals(rows, intervals(rows), number)
            for variant in ('baseline', 'candidate'):
                combined.extend(dict(variant=variant, **row) for row in rows)
        self.assertEqual(len(RUN.validate_results(combined, 6)), 24)

    def test_missing_duplicate_and_unexpected_cases(self):
        rows = observations()
        for changed in (rows[:-1], rows + [rows[0]], [dict(row, width='unknown') for row in rows]):
            with self.assertRaises(RuntimeError):
                RUN.validate_round(changed, 1, 'timing')

    def test_nonfinite_short_and_invalid_gc_intervals(self):
        for field, value in (('cpu_seconds', 'nan'), ('elapsed_seconds', 'inf'),
                             ('cpu_seconds', '.149'), ('gc_cpu_seconds', '-1'),
                             ('gc_cpu_seconds', '2'), ('iterations', '63')):
            rows = observations()
            rows[0][field] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'timing')

    def test_ownership_copy_and_missing_proofs(self):
        for field, value in (('sharing', 'private'), ('compact_copy_bytes', '1'),
                ('compatibility_bytes', '1'), ('missing_count', '-1'),
                ('source_unmaterialized_after', 'FALSE'), ('targets_unmaterialized_before', 'FALSE'),
                ('alias_independent', 'FALSE'), ('result_sha256', '0' * 64)):
            rows = observations()
            rows[0][field] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'timing')

    def test_wrong_density_permutation_and_backing_order(self):
        for field in ('order', 'backing_order'):
            rows = observations()
            rows[0][field] = '9'
            with self.assertRaises(RuntimeError):
                RUN.validate_round(rows, 1, 'timing')

    def test_interval_matrix_and_accounting(self):
        rows = observations()
        good = intervals(rows)
        for bad in (good[:-1], good + [good[0]]):
            with self.assertRaises(RuntimeError):
                RUN.validate_intervals(rows, bad, 1)
        for field, value in (('cpu_seconds', 'nan'), ('cpu_seconds', '.07'),
                             ('handles', '31'), ('compact_copy_bytes', '1')):
            bad = copy.deepcopy(good)
            bad[0][field] = value
            with self.assertRaises(RuntimeError):
                RUN.validate_intervals(rows, bad, 1)

    def test_cross_build_and_round_source_changes(self):
        combined = [dict(variant=v, **row) for number in range(1, 7)
                    for v in ('baseline', 'candidate') for row in observations(number)]
        for bad in (combined[:-1], combined + [combined[0]]):
            with self.assertRaises(RuntimeError):
                RUN.validate_results(bad, 6)
        changed = copy.deepcopy(combined)
        changed[0]['source_sha256'] = changed[0]['result_sha256'] = 'a' * 64
        with self.assertRaises(RuntimeError):
            RUN.validate_results(changed, 6)
        changed = copy.deepcopy(combined)
        for row in changed:
            row['order'] = '1'
        with self.assertRaises(RuntimeError):
            RUN.validate_results(changed, 6)

    def test_scientific_integer_notation_and_invalid_numbers(self):
        rows = observations()
        for row in rows:
            row["compact_payload_bytes"] = str(float(row["compact_payload_bytes"]))
            row["double_payload_bytes"] = "8e+06"
        RUN.validate_round(rows, 1, "timing")
        for value in ("1.5", "nan", "inf", "nonsense"):
            with self.assertRaises(RuntimeError):
                RUN.integer(value)

    def test_qualification_collects_no_clocks(self):
        rows = observations()
        for row in rows:
            row['phase'] = 'qualification'
            for field in ('iterations', 'batches', 'cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
                row[field] = '0'
        RUN.validate_round(rows, 1, 'qualification')
        rows[0]['cpu_seconds'] = '.01'
        with self.assertRaises(RuntimeError):
            RUN.validate_round(rows, 1, 'qualification')


if __name__ == '__main__':
    unittest.main()

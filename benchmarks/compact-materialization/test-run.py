#!/usr/bin/env python3
"""Exercise materialization evidence gates without running R or a benchmark."""
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('materialization_run', Path(__file__).with_name('run.py'))
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


def rows(round_number=1, variant='candidate'):
    result = []
    for n, width, backing, sharing in sorted(RUN.EXPECTED):
        compact_bytes = int(n) * RUN.WIDTHS[width]
        copied = compact_bytes if (variant == 'baseline' and backing == 'constructed' and sharing == 'aliased') else 0
        chunks = (16 if n == '4096' else 123) if backing == 'retained' else 0
        result.append(dict(variant=variant, round=str(round_number), n=n, width=width,
            backing=backing, sharing=sharing, phase='timing', iterations='10', batches='2', batch_size='5',
            cpu_seconds='.16', elapsed_seconds='.17', gc_cpu_seconds='.001',
            min_batch_cpu_seconds='.08', max_batch_cpu_seconds='.08',
            min_batch_elapsed_seconds='.085', max_batch_elapsed_seconds='.085',
            zero_cpu_batches='0', zero_wall_batches='0',
            compact_payload_bytes=str(compact_bytes), double_payload_bytes=str(8 * int(n)),
            compact_copy_bytes=str(copied), timed_compact_copy_bytes=str(copied * 10),
            compatibility_bytes='0', r_profiled_allocation_bytes=str(8 * int(n) + 48),
            r_largest_allocation_bytes=str(8 * int(n) + 48), r_profiled_allocations='1',
            peak_vcell_bytes=str(8 * int(n) + 304), live_vcell_delta_bytes=str(8 * int(n)),
            source_sha256='a' * 64, result_sha256='a' * 64, retained_chunks=str(chunks),
            alias_independent='TRUE', source_unmaterialized_before='TRUE', source_materialized_after='TRUE',
            order=str(1 + ((sharing == 'aliased') == (round_number % 2 == 0)))))
    return result


class Validation(unittest.TestCase):
    def test_complete_baseline_and_candidate(self):
        for variant in ('baseline', 'candidate'):
            RUN.validate_round(rows(1, variant), 1, variant)

    def test_missing_duplicate_and_unexpected_cases(self):
        for batch in (rows()[:-1], rows() + [rows()[0]], rows()[1:] + [rows()[1]]):
            with self.assertRaises(RuntimeError):
                RUN.validate_round(batch, 1, 'candidate')

    def test_invalid_observations(self):
        changes = dict(cpu_seconds='nan', elapsed_seconds='0', gc_cpu_seconds='inf',
            iterations='11', batch_size='0', phase='qualification', round='2',
            compact_payload_bytes='3', double_payload_bytes='3', compact_copy_bytes='1',
            timed_compact_copy_bytes='1', compatibility_bytes='1', r_profiled_allocation_bytes='0',
            r_largest_allocation_bytes='1', r_profiled_allocations='0', peak_vcell_bytes='-1',
            live_vcell_delta_bytes='nan', source_sha256='broken', result_sha256='b' * 64,
            alias_independent='FALSE', source_unmaterialized_before='FALSE',
            source_materialized_after='FALSE', retained_chunks='999', order='3')
        for field, value in changes.items():
            with self.subTest(field=field):
                batch = rows()
                batch[0][field] = value
                with self.assertRaises(RuntimeError):
                    RUN.validate_round(batch, 1, 'candidate')

    def test_baseline_must_show_redundant_copy(self):
        batch = rows(1, 'baseline')
        target = next(row for row in batch if row['backing'] == 'constructed' and row['sharing'] == 'aliased')
        target['compact_copy_bytes'] = '0'
        with self.assertRaises(RuntimeError):
            RUN.validate_round(batch, 1, 'baseline')

    def test_balanced_rounds(self):
        batch = [row for round_number in range(1, 7) for variant in ('baseline', 'candidate')
                 for row in rows(round_number, variant)]
        RUN.validate_results(batch, 6)
        broken = copy.deepcopy(batch)
        broken[0]['result_sha256'] = 'b' * 64
        with self.assertRaises(RuntimeError):
            RUN.validate_results(broken, 6)
        broken = copy.deepcopy(batch)
        broken[0]['round'] = '2'
        with self.assertRaises(RuntimeError):
            RUN.validate_results(broken, 6)
        broken = copy.deepcopy(batch)
        for row in broken:
            row['order'] = '1'
        with self.assertRaises(RuntimeError):
            RUN.validate_results(broken, 6)

    def test_individual_intervals_reproduce_each_aggregate(self):
        batch = rows()
        intervals = []
        for row in batch:
            for number in (1, 2):
                intervals.append(dict({k: row[k] for k in RUN.FIELDS}, round='1', batch=str(number),
                    handles='5', cpu_seconds='.08', elapsed_seconds='.085', gc_cpu_seconds='.0005',
                    compact_copy_bytes='0'))
        RUN.validate_intervals(batch, intervals, 1, 'candidate')
        for field, value in dict(round='2', batch='2', handles='6', cpu_seconds='nan',
                                 elapsed_seconds='.084', gc_cpu_seconds='-.1', compact_copy_bytes='1').items():
            with self.subTest(field=field):
                broken = copy.deepcopy(intervals)
                broken[0][field] = value
                with self.assertRaises(RuntimeError):
                    RUN.validate_intervals(batch, broken, 1, 'candidate')


if __name__ == '__main__':
    unittest.main()

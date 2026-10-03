#!/usr/bin/env python3
"""Protocol rejection tests. No R, fixture construction or performance clocks."""
import copy
import unittest

import core


def observations(panel, phase='measure'):
    rows = []
    for number in range(1, 7) if phase == 'measure' else (1,):
        for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
            for pattern, layout, operation, rep, pp, lp, op, rp in core.order(number, panel):
                compact = str(rep == 'compact').upper()
                retained = int(layout == 'retained' and rep == 'compact')
                xm, ym, joint = core.missing_counts(pattern)
                row = dict(variant=variant, round=str(number), phase=phase, threads='1',
                           panel=panel, pattern=pattern, layout=layout,
                           pattern_position=str(pp), layout_position=str(lp),
                           operation=operation, operation_position=str(op),
                           representation=rep, position=str(rp), rows='1000000',
                           repetitions='10' if phase == 'measure' else '1',
                           x_missing=str(xm), y_missing=str(ym),
                           pair_missing=str(749863 if joint is None else joint),
                           cpu='.3' if phase == 'measure' else '0',
                           wall='.3' if phase == 'measure' else '0', native_qualified='TRUE')
                for field in core.HASHES:
                    row[field] = 'a' * 64
                for prefix in ('compact', 'y_compact'):
                    row[prefix + '_before'] = row[prefix + '_after'] = compact
                for prefix in ('materialized', 'y_materialized'):
                    row[prefix + '_before'] = row[prefix + '_after'] = 'FALSE'
                for prefix in ('retained', 'y_retained'):
                    row[prefix + '_before'] = row[prefix + '_after'] = str(retained)
                for prefix, value in (('chunks', 123), ('y_chunks', 62)):
                    row[prefix + '_before'] = row[prefix + '_after'] = str(value if retained else 0)
                rows.append(row)
    return rows


class Protocol(unittest.TestCase):
    def setUp(self):
        self.rows = observations('pattern')

    def reject(self, rows, panel='pattern'):
        with self.assertRaises(RuntimeError):
            core.validate_all(rows, 6, 'measure', panel)

    def test_complete_panels_and_summaries(self):
        total = 0
        for panel, count in (('density', 288), ('pattern', 288), ('ordinary', 192)):
            rows = observations(panel)
            core.validate_all(rows, 6, 'measure', panel)
            self.assertEqual(len(rows), count)
            self.assertEqual(len(core.summarize(rows, panel)), count // 24)
            total += len(rows)
        self.assertEqual(total, 768)

    def test_qualification_has_no_clocks_and_one_recorded_repetition(self):
        for panel in core.PANELS:
            rows = observations(panel, 'qualify')
            core.validate_all(rows, 1, 'qualify', panel)
            for field, value in (('cpu', '.1'), ('repetitions', '2')):
                invalid = copy.deepcopy(rows)
                invalid[0][field] = value
                with self.assertRaises(RuntimeError):
                    core.validate_all(invalid, 1, 'qualify', panel)

    def test_missing_duplicate_extra(self):
        self.reject(self.rows[:-1])
        self.reject(self.rows + [self.rows[0]])

    def test_timings(self):
        for value in ('0', '-1', 'nan', 'inf'):
            rows = copy.deepcopy(self.rows)
            rows[0]['cpu'] = value
            self.reject(rows)

    def test_integer_parser(self):
        self.assertEqual(core.integer('1e6'), 1000000)
        for value in ('1.5', 'nan', 'inf', '-1', True):
            with self.assertRaises(RuntimeError):
                core.integer(value)

    def test_order_even_with_complete_cases(self):
        rows = copy.deepcopy(self.rows)
        rows[0], rows[1] = rows[1], rows[0]
        self.reject(rows)
        rows = copy.deepcopy(self.rows)
        rows[0]['layout_position'] = '2'
        self.reject(rows)

    def test_build_order(self):
        self.reject(self.rows[24:48] + self.rows[:24] + self.rows[48:])

    def test_counts_and_partial_alternating_cycle(self):
        self.assertEqual(core.missing_counts('alternating64'), (500032, 500032, 500032))
        for field, value in (('x_missing', '255'), ('pair_missing', '255')):
            rows = copy.deepcopy(self.rows)
            rows[0][field] = value
            self.reject(rows)
        rows = copy.deepcopy(self.rows)
        next(r for r in rows if r['pattern'] == 'alternating64')['x_missing'] = '500000'
        self.reject(rows)

    def test_sparse_grid_counts(self):
        self.assertEqual(core.missing_counts('sparse'), (1003, 1010, 2011))

    def test_state_native_and_retained_geometry(self):
        for field, value in (('materialized_after', 'TRUE'), ('native_qualified', 'FALSE'),
                             ('retained_before', '7'), ('chunks_before', '122')):
            rows = copy.deepcopy(self.rows)
            rows[0][field] = value
            self.reject(rows)

    def test_changed_results_or_rank_inputs(self):
        for field in ('result_hash', 'rank_x_hash', 'metadata_y'):
            rows = copy.deepcopy(self.rows)
            rows[0][field] = 'b' * 64
            self.reject(rows)

    def test_same_values_across_layouts(self):
        rows = copy.deepcopy(self.rows)
        for row in rows:
            if row['layout'] == 'retained':
                row['rank_x_hash'] = 'b' * 64
        self.reject(rows)

    def test_same_values_across_representations(self):
        rows = copy.deepcopy(self.rows)
        for row in rows:
            if row['representation'] == 'typed_double':
                row['result_hash'] = 'b' * 64
        self.reject(rows)


if __name__ == '__main__':
    unittest.main()

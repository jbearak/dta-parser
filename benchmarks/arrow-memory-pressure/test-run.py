import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('pressure_benchmark', Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def observations():
    return [{'round': r, 'variant': v, 'condition': c, 'storage': s,
             'repetitions': 200 if v == 'baseline' and c == '65' else 2000,
             'cpu': 1.0, 'gc_attempts': 0 if v == 'candidate' else 'NA',
             'signature': f'result-{s}', 'held_signature': f'held-{c}'}
            for r in range(1, 7) for v in ('baseline', 'candidate')
            for c in ('none', '63', '65') for s in ('double', 'float')]


class CompletionChecks(unittest.TestCase):
    def test_complete_balanced_observations_pass(self):
        runner.validate_rows(observations())

    def test_missing_duplicate_and_mislabeled_cases_fail(self):
        rows = observations()
        for changed in (rows[:-1], rows + [rows[0]], rows[:-1] + [rows[0]]):
            with self.subTest(size=len(changed)), self.assertRaises(RuntimeError):
                runner.validate_rows(changed)

    def test_wrong_values_and_retained_input_fail(self):
        for field in ('signature', 'held_signature'):
            rows = observations()
            rows[-1][field] = 'incorrect'
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                runner.validate_rows(rows)

    def test_timing_and_forced_collection_failures_cannot_be_accepted(self):
        for field, value in (('cpu', 0), ('cpu', float('nan')), ('cpu', float('inf')),
                             ('repetitions', 0), ('gc_attempts', 1)):
            rows = observations()
            rows[-1][field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                runner.validate_rows(rows)


if __name__ == '__main__':
    unittest.main()

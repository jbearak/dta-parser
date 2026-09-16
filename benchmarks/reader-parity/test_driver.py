import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('parity_driver', Path(__file__).with_name('run.py'))
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class DriverTest(unittest.TestCase):
    def test_balanced_positions_and_pair_order(self):
        methods = ['base-dta', 'base-arrow', 'candidate-dta', 'candidate-arrow', 'stata']
        orders = driver.orders(methods, 20)
        for method in methods:
            for position in range(5):
                self.assertEqual(sum(order[position] == method for order in orders), 4)
        for a in methods:
            for b in methods:
                if a != b:
                    self.assertEqual(sum(order.index(a) < order.index(b) for order in orders), 10)

    def test_screen_zero_timers_and_losing_cohort_cannot_pass(self):
        rows = []
        for cohort, candidate in ((1, 0.9), (2, 1.1)):
            for method, elapsed in (('stata', 1.0), ('candidate-dta', candidate)):
                rows.extend(dict(case='all', mode='fresh', cohort=cohort, method=method,
                    elapsed_seconds=elapsed, peak_rss_bytes=10, cpu_seconds=1) for _ in range(12))
        screen = driver.summaries(rows, False)
        self.assertFalse(any(r['parity'] for r in screen))
        result = driver.summaries(rows, True)
        self.assertEqual([r['parity'] for r in result if r['method'] == 'candidate-dta'], [True, False])
        for row in rows:
            row['elapsed_seconds'] = 0
        self.assertFalse(any(r['parity'] for r in driver.summaries(rows, True)))
        for row in rows:
            row['elapsed_seconds'] = 0.001 if row['method'] == 'candidate-dta' else 1.0
        self.assertFalse(any(r['parity'] for r in driver.summaries(rows, True)
                             if r['method'] == 'candidate-dta'))

    def test_discovery_is_timed_and_direct_projection_is_direct(self):
        case = dict(dta='/tmp/input.dta', selection=['a', 'b'], selection_mode='known', rows=10, columns=2)
        direct = driver.stata_program(case, 'fresh', 1, Path('/tmp/out'))
        self.assertIn('use a b using', direct)
        self.assertNotIn('describe using', direct)
        case['selection_mode'] = 'any_of'
        discovery = driver.stata_program(case, 'fresh', 1, Path('/tmp/out'))
        self.assertLess(discovery.index('timer on'), discovery.index('describe using'))
        self.assertLess(discovery.index('describe using'), discovery.index('timer off'))


if __name__ == '__main__':
    unittest.main()

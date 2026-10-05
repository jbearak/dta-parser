"""Fast policy and Cargo-log checks; never starts R, Cargo or a compiler."""
from pathlib import Path
import runpy
import unittest

HERE = Path(__file__).resolve().parent
FOCUSED = runpy.run_path(str(HERE / 'focused-test-run.py'))
RUST = runpy.run_path(str(HERE / 'reader-rust-tests.py'))


def summary(passed=1, failed=0, ignored=0, status='ok'):
    return (f'test result: {status}. {passed} passed; {failed} failed; {ignored} ignored; '
            '0 measured; 12 filtered out; finished in 0.01s\n')


class QualificationChecks(unittest.TestCase):
    def test_warning_policy_requires_zero_on_both_sides(self):
        row = dict(failed='0', error='FALSE', warning='0', skipped='FALSE', passed='2')
        policy = dict(warnings=0, min_pass=2)
        self.assertTrue(FOCUSED['row_passes_policy'](row, policy))
        for observed, allowed in ((1, 0), (0, 1), (1, 1)):
            with self.subTest(observed=observed, allowed=allowed):
                self.assertFalse(FOCUSED['row_passes_policy'](
                    row | {'warning': str(observed)}, policy | {'warnings': allowed}))

    def test_failure_error_skip_and_short_assertion_count_still_reject(self):
        row = dict(failed='0', error='FALSE', warning='0', skipped='FALSE', passed='2')
        for change in ({'failed': '1'}, {'error': 'TRUE'}, {'skipped': 'TRUE'}, {'passed': '1'}):
            self.assertFalse(FOCUSED['row_passes_policy'](row | change, dict(warnings=0, min_pass=2)))

    def test_crlf_timing_and_should_panic_preserve_names_and_counts(self):
        text = ('test first ... ok\r\n'
                'test second - should panic ... ok (0.01s)\r\n'
                'test third ... ignored\r\n' + summary(passed=2, ignored=1).replace('\n', '\r\n'))
        parsed = RUST['parse_test_output'](text)
        self.assertEqual(parsed['tests'], [('first', 'ok'), ('second', 'ok'), ('third', 'ignored')])
        self.assertEqual((parsed['passed'], parsed['failed'], parsed['ignored']), (2, 0, 1))

    def test_failed_status_matches_authoritative_summary(self):
        parsed = RUST['parse_test_output']('test first ... FAILED <0.01s>\n' +
                                          summary(passed=0, failed=1, status='FAILED'))
        self.assertEqual(parsed['failed'], 1)

    def test_truncated_or_duplicate_statuses_reject(self):
        for text in ('test first ... ok\n' + summary(passed=2),
                     'test first ... ok\ntest first ... ok\n' + summary(passed=2),
                     'test first ... ok\n' + summary(status='FAILED')):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                RUST['parse_test_output'](text)

    def test_missing_or_duplicate_summary_reject(self):
        for text in ('test first ... ok\n', 'test first ... ok\n' + summary() + summary()):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                RUST['parse_test_output'](text)


if __name__ == '__main__':
    unittest.main()

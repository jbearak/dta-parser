import unittest

import india


class IndiaTest(unittest.TestCase):
    def test_ten_rounds_balance_pair_precedence_and_positions(self):
        orders = india.round_orders()
        self.assertEqual(len(orders), 10)
        for method in india.METHODS:
            counts = [sum(order[position] == method for order in orders) for position in range(4)]
            self.assertEqual(sorted(counts), [2, 2, 3, 3])
            for other in india.METHODS:
                if method != other:
                    self.assertEqual(sum(order.index(method) < order.index(other) for order in orders), 5)

    def test_comparison_uses_process_cpu_for_every_reader(self):
        observations = [dict(method=method, elapsed_seconds=value,
            read_cpu_seconds=None if method == 'stata' else 1,
            process_cpu_seconds=10 * value, peak_rss_bytes=100 * value)
            for method in india.METHODS for value in (1, 3)]
        summary = india.summarize(observations)
        self.assertEqual(len(summary), 4)
        for row in summary:
            self.assertEqual(row['median_seconds'], 2)
            self.assertEqual(row['min_seconds'], 1)
            self.assertEqual(row['max_seconds'], 3)
            self.assertEqual(row['median_process_cpu_seconds'], 20)
            self.assertEqual(row['median_peak_rss_bytes'], 200)


if __name__ == '__main__':
    unittest.main()

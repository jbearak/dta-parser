#!/usr/bin/env python3
"""Reject protocol violations without loading R or timing anything."""
import unittest
from core import *


def fixture(rounds=6, phase='measure'):
    rows = []
    for number in range(1, rounds + 1):
        for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
            for pattern, operation, rep, pp, op, rp in order(number):
                row = dict(variant=variant, round=str(number), phase=phase, threads='1', rows='1000000',
                    pattern=pattern, operation=operation, representation=rep, pattern_position=str(pp),
                    operation_position=str(op), position=str(rp), repetitions='1',
                    cpu='0.3' if phase == 'measure' else '0', wall='0.3' if phase == 'measure' else '0',
                    native_calls='0' if rep == 'ordinary' else '1', qualification_calls='0' if rep == 'ordinary' else '1',
                    input_missing=str(COUNTS[pattern]), result_missing=str(COUNTS[pattern]),
                    result_storage={'compact':'float','typed_double':'double','ordinary':''}[rep])
                row.update({k:'a'*64 for k in HASHES})
                for side in ('before', 'after'):
                    row.update({f'compact_{side}':str(rep=='compact').upper(),f'materialized_{side}':'FALSE',
                                f'retained_{side}':'0',f'chunks_{side}':'0'})
                rows.append(row)
    return rows


class ProtocolTests(unittest.TestCase):
    def reject(self, field, value):
        rows = fixture(); rows[0][field] = value
        with self.assertRaises(RuntimeError): validate_all(rows,6,'measure')
    def test_valid_measurement(self): validate_all(fixture(),6,'measure')
    def test_valid_qualification(self): validate_all(fixture(1,'qualify'),1,'qualify')
    def test_integer_grammar(self):
        self.assertEqual(integer('1e6'),1000000)
        for value in ('NaN','Infinity','-1','1.5'):
            with self.assertRaises(RuntimeError): integer(value)
    def test_missing_case(self):
        with self.assertRaises(RuntimeError): validate_all(fixture()[:-1],6,'measure')
    def test_order(self): self.reject('position','3')
    def test_native(self): self.reject('native_calls','0')
    def test_missing_count(self): self.reject('result_missing','1')
    def test_storage(self): self.reject('result_storage','byte')
    def test_source_state(self): self.reject('materialized_after','TRUE')
    def test_hash(self): self.reject('input_hash','z'*64)
    def test_nonfinite_clock(self): self.reject('cpu','NaN')
    def test_cross_build_result(self): self.reject('result_hash','b'*64)
    def test_summary(self):
        rows=fixture(); result=summarize(rows)
        self.assertEqual(len(result),28)
        self.assertTrue(all(r['compact_cpu_speedup']==1 for r in result))
    def test_compact_rounding_can_differ(self):
        rows=fixture()
        for r in rows:
            if r['representation']=='compact':r['result_hash']='b'*64
        validate_all(rows,6,'measure')
    def test_bare_typed_must_match(self):
        rows=fixture()
        for r in rows:
            if r['representation']=='ordinary':r['result_hash']='b'*64
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')


if __name__ == '__main__': unittest.main()

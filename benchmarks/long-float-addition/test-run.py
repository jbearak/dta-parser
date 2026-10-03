"""Reject malformed screen evidence without starting R or timing anything."""
import unittest
from core import *

def fixture(rounds=6,phase='measure'):
    rows=[]
    for number in range(1,rounds+1):
        for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            for layout,pattern,operation,rep,lp,pp,op,rp in order(number):
                native=rep!='ordinary'
                counts=COUNTS.get(pattern,(500000,500000,250000))
                row=dict(variant=variant,round=str(number),phase=phase,threads='1',rows=str(N),
                    layout=layout,pattern=pattern,operation=operation,representation=rep,
                    layout_position=str(lp),pattern_position=str(pp),operation_position=str(op),position=str(rp),
                    repetitions='1',cpu='0.3' if phase=='measure' else '0',wall='0.3' if phase=='measure' else '0',
                    native_calls=str(int(native)),qualification_calls=str(int(native)),result_storage='double' if native else '',
                    long_missing=str(counts[0]),float_missing=str(counts[1]),overlap=str(counts[2]),
                    result_missing=str(counts[0]+counts[1]-counts[2]),mutation_checked=str(native).upper(),
                    cleared_hash='c'*64 if native else '')
                row.update({key:'a'*64 for key in HASHES})
                for key in STATES:
                    side,name=key.split('_',1)
                    for when in ('before','after'):row[key+'_'+when]=str(expected_state(layout,rep,side,name))
                rows.append(row)
    return rows

class ProtocolTests(unittest.TestCase):
    def reject(self,field,value):
        rows=fixture();rows[0][field]=value
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')
    def test_valid_measurement(self):
        rows=fixture();self.assertEqual(len(rows),696);validate_all(rows,6,'measure')
    def test_valid_qualification(self):
        rows=fixture(1,'qualify');self.assertEqual(len(rows),116);validate_all(rows,1,'qualify')
    def test_integer_grammar(self):
        self.assertEqual(integer('1e6'),1000000)
        for value in ('NaN','Infinity','-1','1.5'):
            with self.assertRaises(RuntimeError):integer(value)
    def test_missing_case(self):
        with self.assertRaises(RuntimeError):validate_all(fixture()[:-1],6,'measure')
    def test_order(self):self.reject('position','3')
    def test_native(self):self.reject('native_calls','0')
    def test_missing_union(self):self.reject('result_missing','1')
    def test_overlap(self):self.reject('overlap','1')
    def test_storage(self):self.reject('result_storage','float')
    def test_source_state(self):self.reject('long_materialized_after','1')
    def test_chunks(self):self.reject('float_chunks_before','7')
    def test_hash(self):self.reject('input_hash','z'*64)
    def test_nonfinite_clock(self):self.reject('cpu','NaN')
    def test_cross_build_result(self):self.reject('result_hash','b'*64)
    def test_mutation(self):self.reject('mutation_checked','FALSE')
    def test_cleared_hash(self):self.reject('cleared_hash','b'*64)
    def test_cross_representation(self):
        rows=fixture()
        for row in rows:
            if row['representation']=='compact':row['result_hash']='b'*64
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')
    def test_cross_layout(self):
        rows=fixture()
        for row in rows:
            if row['layout']=='short':row['rank_hash']='b'*64
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')
    def test_summary(self):
        result=summarize(fixture());self.assertEqual(len(result),26)
        self.assertTrue(all(row['compact_cpu_speedup']==1 for row in result))
    def test_metadata_is_per_case(self):
        rows=fixture()
        for row in rows:
            if row['representation']=='compact':row['metadata_hash']='b'*64
        validate_all(rows,6,'measure')
if __name__=='__main__':unittest.main()

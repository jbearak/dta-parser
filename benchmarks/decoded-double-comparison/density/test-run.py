#!/usr/bin/env python3
"""Small protocol rejection tests; no R, fixture construction, or timing."""
import copy
import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('density_run',Path(__file__).with_name('run.py'))
run=importlib.util.module_from_spec(spec);spec.loader.exec_module(run)

def observations(phase='measure'):
    rows=[]
    for number in range(1,7) if phase=='measure' else (1,):
        for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            for density,operation,rep,dp,op,rp in run.order(number):
                compact=str(rep=='compact').upper();count='1000000' if density=='all_tags' else '500000'
                row=dict(variant=variant,round=str(number),phase=phase,threads='1',density=density,
                    density_position=str(dp),operation=operation,operation_position=str(op),
                    representation=rep,position=str(rp),rows='1000000',repetitions='10' if phase=='measure' else '1',
                    x_missing=count,y_missing=count,pair_missing='750000' if density=='random_half' else count,
                    cpu='.3' if phase=='measure' else '0',wall='.3' if phase=='measure' else '0',
                    native_qualified='TRUE')
                for field in run.HASHES:row[field]='a'*64
                for prefix in ('compact','y_compact'):row[prefix+'_before']=row[prefix+'_after']=compact
                for prefix in ('materialized','y_materialized'):row[prefix+'_before']=row[prefix+'_after']='FALSE'
                rows.append(row)
    return rows

class Protocol(unittest.TestCase):
    def setUp(self):self.rows=observations()
    def reject(self,rows):
        with self.assertRaises(RuntimeError):run.validate_all(rows,6,'measure')
    def test_complete_and_summary(self):
        run.validate_all(self.rows,6,'measure');self.assertEqual(len(self.rows),144)
        self.assertEqual(len(run.summarize(self.rows)),6)
    def test_qualification_has_no_clocks(self):
        rows=observations('qualify');run.validate_all(rows,1,'qualify')
        rows[0]['cpu']='.1'
        with self.assertRaises(RuntimeError):run.validate_all(rows,1,'qualify')
    def test_qualification_has_one_repetition(self):
        rows=observations('qualify');rows[0]['repetitions']='2'
        with self.assertRaises(RuntimeError):run.validate_all(rows,1,'qualify')
    def test_missing_duplicate_extra(self):
        self.reject(self.rows[:-1]);self.reject(self.rows+[self.rows[0]])
    def test_timings(self):
        for value in ('0','-1','nan','inf'):
            rows=copy.deepcopy(self.rows);rows[0]['cpu']=value;self.reject(rows)
    def test_integer_parser(self):
        self.assertEqual(run.integer('1e6'),1000000)
        for value in ('1.5','nan','inf','-1',True):
            with self.assertRaises(RuntimeError):run.integer(value)
    def test_order_rejected_even_with_complete_cases(self):
        rows=copy.deepcopy(self.rows);rows[0],rows[1]=rows[1],rows[0];self.reject(rows)
        rows=copy.deepcopy(self.rows);rows[0]['position']='2';self.reject(rows)
    def test_build_order(self):
        rows=self.rows[12:24]+self.rows[:12]+self.rows[24:];self.reject(rows)
    def test_density_counts(self):
        for field,value in [('x_missing','499999'),('pair_missing','499999')]:
            rows=copy.deepcopy(self.rows);rows[0][field]=value;self.reject(rows)
    def test_state_and_native(self):
        for field,value in [('materialized_after','TRUE'),('native_qualified','FALSE')]:
            rows=copy.deepcopy(self.rows);rows[0][field]=value;self.reject(rows)
    def test_changed_results_or_rank_inputs(self):
        for field in ('result_hash','rank_x_hash','metadata_y'):
            rows=copy.deepcopy(self.rows);rows[0][field]='b'*64;self.reject(rows)
    def test_same_contract_across_representations(self):
        rows=copy.deepcopy(self.rows)
        for row in rows:
            if row['representation']=='typed_double':row['result_hash']='b'*64
        self.reject(rows)

if __name__=='__main__':unittest.main()

import copy
import unittest
from core import order,validate_all,validate_round

def batch(number=1,phase='measure'):
    rows=[]
    for n,p,rep,pp,pos in order(number):
        input_missing={'none':0,'sparse':1003,'prefix256':256,'random_half':500000,'all_tags':1000000}[p]
        zeros=50 if p=='random_half' else 0 if p=='all_tags' else len(range(8847,n+1,10001))
        row=dict(round=str(number),phase=phase,threads='1',rows=str(n),pattern=p,pattern_position=str(pp),operation='reciprocal',operation_position='1',representation=rep,position=str(pos),repetitions='2' if phase=='measure' else '1',cpu='.3' if phase=='measure' else '0',wall='.3' if phase=='measure' else '0',native_calls=str((2 if phase=='measure' else 1) if n>=2048 else 0),qualification_calls=str(int(n>=2048)),input_hash='a'*64,rank_hash='b'*64,mutation_checked='TRUE',cleared_hash='8'*64,result_hash=('c' if rep=='compact' else 'd')*64,missing_hash='e'*64,metadata_hash='f'*64,result_metadata_hash='f'*64,input_missing=str(input_missing),zero_observed=str(zeros),result_missing=str(input_missing+zeros),result_storage='float' if rep=='compact' else 'double')
        for state,value in [('compact',str(rep=='compact').upper()),('materialized','FALSE'),('retained','0'),('chunks','0')]:
            row[state+'_before']=row[state+'_after']=value
        rows.append(row)
    return rows

def complete(phase='measure'):
    rows=[]
    for number in range(1,7 if phase=='measure' else 2):
        for role in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            rows.extend(dict(variant=role,**r) for r in batch(number,phase))
    return rows

class Guards(unittest.TestCase):
    def test_complete_matrix_and_qualification(self):
        validate_all(complete(),6,'measure');validate_all(complete('qualify'),1,'qualify')
    def test_omission_and_duplicate(self):
        rows=batch()
        for bad in (rows[:-1],rows+[rows[0]]):
            with self.assertRaises(RuntimeError):validate_round(bad,1,'measure')
    def test_nonfinite_or_short_qualification_counts(self):
        for field,value in [('cpu','nan'),('wall','inf'),('repetitions','0'),('rows','1.5')]:
            rows=batch();rows[0][field]=value
            with self.assertRaises(RuntimeError):validate_round(rows,1,'measure')
        rows=batch(1,'qualify');rows[0]['repetitions']='2'
        with self.assertRaises(RuntimeError):validate_round(rows,1,'qualify')
    def test_native_default_boundary(self):
        for n in ('1024','2048'):
            rows=batch();next(r for r in rows if r['rows']==n)['qualification_calls']='1' if n=='1024' else '0'
            with self.assertRaises(RuntimeError):validate_round(rows,1,'measure')
    def test_missing_and_zero_counts(self):
        for field in ('input_missing','zero_observed','result_missing'):
            rows=batch();rows[0][field]='7'
            with self.assertRaises(RuntimeError):validate_round(rows,1,'measure')
    def test_source_and_storage(self):
        for field,value in [('materialized_after','TRUE'),('result_storage','double'),('retained_before','1'),('input_hash','wrong')]:
            rows=batch();rows[0][field]=value
            with self.assertRaises(RuntimeError):validate_round(rows,1,'measure')
    def test_missing_mutation_qualification(self):
        rows=batch();rows[0]['mutation_checked']='FALSE'
        with self.assertRaises(RuntimeError):validate_round(rows,1,'measure')
        rows=complete();rows[-1]['cleared_hash']='9'*64
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')
    def test_result_drift(self):
        rows=complete();rows[-1]['result_hash']='9'*64
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')
    def test_order_and_role(self):
        rows=complete();rows[0],rows[1]=rows[1],rows[0]
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')
        rows=complete();rows[0]['variant']='candidate'
        with self.assertRaises(RuntimeError):validate_all(rows,6,'measure')

if __name__=='__main__':unittest.main()

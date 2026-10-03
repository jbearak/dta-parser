"""Private reciprocal matrix, complete semantics and default admission checks."""
from collections import Counter
from decimal import Decimal, InvalidOperation
import math
import statistics

STRATA = ((1024,'none'),(2048,'none'),(4096,'none'),(16384,'none'),
          (1000000,'none'),(1000000,'sparse'),(1000000,'prefix256'),
          (1000000,'random_half'),(1000000,'all_tags'))
REPS = ('compact','typed_double')
HASHES = ('input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash','cleared_hash')
STATES = ('compact','materialized','retained','chunks')
RESULT_FIELDS = HASHES + ('mutation_checked','input_missing','zero_observed','result_missing','result_storage') + tuple(x+'_before' for x in STATES)

def require(ok,message):
    if not ok: raise RuntimeError(message)

def integer(value):
    try: n=Decimal(str(value))
    except InvalidOperation: raise RuntimeError('Invalid integer')
    require(n.is_finite() and n>=0 and n==n.to_integral_value(),'Invalid integer')
    return int(n)

def key(row): return integer(row['rows']),row['pattern'],row['representation']
def cases(): return {(n,p,r) for n,p in STRATA for r in REPS}

def order(number):
    indices=list(range(len(STRATA)))
    shift=(number-1)%len(indices);indices=indices[shift:]+indices[:shift]
    if number%2==0: indices.reverse()
    result=[]
    for position,index in enumerate(indices,1):
        n,pattern=STRATA[index]
        reps=REPS if (number+index)%2 else tuple(reversed(REPS))
        result.extend((n,pattern,r,position,rp) for rp,r in enumerate(reps,1))
    return result

def validate_round(rows,number,phase):
    require(Counter(key(r) for r in rows)==Counter({x:1 for x in cases()}),'Incomplete or repeated matrix')
    require([(*key(r),integer(r['pattern_position']),integer(r['position'])) for r in rows]==order(number),'Execution order changed')
    for r in rows:
        n,p,rep=key(r);reps=integer(r['repetitions'])
        require(r['mutation_checked']=='TRUE','Missing-cache mutation was not checked')
        require(r['phase']==phase and integer(r['round'])==number and integer(r['threads'])==1 and r['operation']=='reciprocal' and integer(r['operation_position'])==1,'Wrong phase/shape')
        require(reps>0 and (phase!='qualify' or reps==1),'Invalid repetitions')
        for metric in ('cpu','wall'):
            value=float(r[metric]);require(math.isfinite(value) and (value>0 if phase=='measure' else value==0),'Invalid timing')
        admitted=n>=2048
        require(integer(r['native_calls'])==(reps if admitted else 0) and integer(r['qualification_calls'])==int(admitted),'Default native admission changed')
        input_missing={'none':0,'sparse':1003,'prefix256':256,'random_half':500000,'all_tags':1000000}[p]
        zeros=integer(r['zero_observed']);zero_grid=range(8847,n+1,10001)
        if p=='random_half': require(zeros<=len(zero_grid),'Invalid observed zero count')
        else:
            expected_zeros=0 if p=='all_tags' else sum(p!='sparse' or (i<13 or (i-13)%997!=0) for i in zero_grid)
            require(zeros==expected_zeros,'Observed zero count differs from exact grid')
        require(integer(r['input_missing'])==input_missing and integer(r['result_missing'])==input_missing+zeros,'Missing count changed')
        require(r['result_storage']=={'compact':'float','typed_double':'double'}[rep],'Wrong result storage')
        for state in STATES: require(r[state+'_before']==r[state+'_after'],'Source state changed')
        require(r['compact_before']==str(rep=='compact').upper() and r['materialized_before']=='FALSE' and integer(r['retained_before'])==0 and integer(r['chunks_before'])==0,'Wrong source representation')
        for h in HASHES: require(len(r[h])==64 and set(r[h])<=set('0123456789abcdef'),'Malformed full hash')

def validate_all(rows,rounds,phase):
    require(len(rows)==2*rounds*len(cases()),'Wrong observation count')
    rebuilt=[]
    for number in range(1,rounds+1):
        for role in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            group=[r for r in rows if r['variant']==role and integer(r['round'])==number]
            validate_round(group,number,phase);rebuilt.extend(group)
    require(rebuilt==rows,'Paired build order changed')
    for case in cases():
        group=[r for r in rows if key(r)==case]
        require(len({tuple(r[k] for k in RESULT_FIELDS) for r in group})==1,'Source/result metadata changed across builds or rounds')
        if phase=='measure':
            for role in ('baseline','candidate'):
                require(Counter(integer(r['position']) for r in group if r['variant']==role)==Counter({1:rounds//2,2:rounds//2}),'Representation positions unbalanced')
    for n,p in STRATA:
        group=[r for r in rows if integer(r['rows'])==n and r['pattern']==p]
        require(len({(r['input_hash'],r['rank_hash'],r['input_missing'],r['zero_observed']) for r in group})==1,'Equivalent input differs by representation')
        require(len({(r['missing_hash'],r['result_missing']) for r in group})==1,'Result missing masks differ by representation')

def summarize(rows):
    output=[]
    for n,p in STRATA:
        item=dict(rows=n,pattern=p)
        groups={(role,rep):sorted([r for r in rows if integer(r['rows'])==n and r['pattern']==p and r['variant']==role and r['representation']==rep],key=lambda r:integer(r['round'])) for role in ('baseline','candidate') for rep in REPS}
        for (role,rep),group in groups.items():
            for metric in ('cpu','wall'):
                values=[float(r[metric])/integer(r['repetitions']) for r in group]
                item[f'{role}_{rep}_{metric}']=statistics.median(values)
                item[f'{role}_{rep}_{metric}_min']=min(values);item[f'{role}_{rep}_{metric}_max']=max(values)
        for rep in REPS:
            for metric in ('cpu','wall'):
                item[f'{rep}_{metric}_speedup']=item[f'baseline_{rep}_{metric}']/item[f'candidate_{rep}_{metric}']
                item[f'{rep}_{metric}_paired_speedup']=statistics.median((float(b[metric])/integer(b['repetitions']))/(float(c[metric])/integer(c['repetitions'])) for b,c in zip(groups['baseline',rep],groups['candidate',rep]))
        for role in ('baseline','candidate'):
            item[f'{role}_compact_typed_cpu']=item[f'{role}_compact_cpu']/item[f'{role}_typed_double_cpu']
        output.append(item)
    return output

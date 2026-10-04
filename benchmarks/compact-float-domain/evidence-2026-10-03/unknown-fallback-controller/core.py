"""Validate the complete long+float matrix and whole-result evidence."""
from collections import Counter
from decimal import Decimal, InvalidOperation
import itertools
import math
import statistics

PANELS={'plain':('none','sparse','random_half')}
LAYOUTS=tuple(PANELS)
OPERATIONS=('long_float','float_long')
FIELDS=('layout','pattern','operation','representation')
HASHES=('input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash')
STATES=tuple(side+'_'+name for side in ('long','float') for name in ('compact','materialized','retained','chunks'))
SEMANTICS=('long_missing','float_missing','overlap','result_missing')
RESULT_FIELDS=HASHES+SEMANTICS+('result_storage','mutation_checked','cleared_hash')+tuple(k+'_before' for k in STATES)
DOMAIN_FIELDS=('domain_available','long_domain_before','long_domain_after','float_domain_before','float_domain_after')
N=1000000
X_SPARSE=set(range(13,N+1,997));Y_SPARSE=set(range(19,N+1,991))
COUNTS={'none':(0,0,0),'sparse':(len(X_SPARSE),len(Y_SPARSE),len(X_SPARSE&Y_SPARSE)),
        'prefix256':(0,256,0),'suffix256':(0,256,0),'all_tags':(N,N,N)}

def require(ok,message):
    if not ok:raise RuntimeError(message)
def integer(value):
    try:number=Decimal(str(value))
    except InvalidOperation:raise RuntimeError('Invalid integer')
    require(number.is_finite() and number>=0 and number==number.to_integral_value(),'Invalid integer')
    return int(number)
def representations(pattern):return ('compact','typed_double')
def cases():return {(layout,pattern,op,rep) for layout,patterns in PANELS.items() for pattern in patterns for op in OPERATIONS for rep in representations(pattern)}
def rotated(items,number):
    offset=(number-1)%len(items);result=items[offset:]+items[:offset]
    return result if number%2 else tuple(reversed(result))
def order(number):
    result=[]
    for lp,layout in enumerate(rotated(LAYOUTS,number),1):
        for pp,pattern in enumerate(rotated(PANELS[layout],number),1):
            for op,operation in enumerate(OPERATIONS if number%2 else tuple(reversed(OPERATIONS)),1):
                reps=representations(pattern)
                if len(reps)==3:
                    reps=tuple(itertools.permutations(reps))[(number-1+OPERATIONS.index(operation)+LAYOUTS.index(layout))%6]
                elif (number+PANELS[layout].index(pattern)+OPERATIONS.index(operation)+LAYOUTS.index(layout))%2==0:
                    reps=tuple(reversed(reps))
                for rp,rep in enumerate(reps,1):result.append((layout,pattern,operation,rep,lp,pp,op,rp))
    return result
def expected_state(layout,rep,side,key):
    retained=rep=='compact' and layout!='plain'
    if key=='compact':return int(rep=='compact')
    if key=='materialized':return 0
    if key=='retained':return int(retained)
    if not retained:return 0
    chunk={'retained':{'long':8191,'float':16385},'short':{'long':7,'float':11}}[layout][side]
    return (N+chunk-1)//chunk
def validate_round(rows,number,phase):
    require(Counter(tuple(r[k] for k in FIELDS) for r in rows)==Counter({c:1 for c in cases()}),'Incomplete/repeated case matrix')
    require([tuple(r[k] for k in FIELDS)+tuple(integer(r[k]) for k in ('layout_position','pattern_position','operation_position','position')) for r in rows]==order(number),'Execution order changed')
    for r in rows:
        require(r['phase']==phase and integer(r['round'])==number and integer(r['rows'])==N and integer(r['threads'])==1,'Wrong phase/shape')
        repetitions=integer(r['repetitions'])
        require(repetitions>0 and (phase!='qualify' or repetitions==1),'Invalid repetition count')
        for metric in ('cpu','wall'):
            value=float(r[metric]);require(math.isfinite(value) and (value>0 if phase=='measure' else value==0),'Invalid clock')
        for field in DOMAIN_FIELDS:
            require(integer(r[field]) in (0,1),'Malformed domain fact')
        require(r['long_domain_before']==r['long_domain_after'] and r['float_domain_before']==r['float_domain_after'],'Domain changed across operation')
        native=r['representation']!='ordinary'
        require(integer(r['native_calls'])==(repetitions if native else 0) and integer(r['qualification_calls'])==int(native),'Native route changed')
        require(r['result_storage']==('double' if native else ''),'Result storage changed')
        counts=tuple(integer(r[k]) for k in SEMANTICS[:3])
        if r['pattern']=='random_half':require(counts[:2]==(500000,500000) and counts[2]<=500000,'Random input counts changed')
        else:require(counts==COUNTS[r['pattern']],'Input missing/overlap counts changed')
        require(integer(r['result_missing'])==counts[0]+counts[1]-counts[2],'Result is not the missing union')
        for key in STATES:
            side,name=key.split('_',1)
            expected=expected_state(r['layout'],r['representation'],side,name)
            require(integer(r[key+'_before'])==expected and integer(r[key+'_after'])==expected,'Source layout/state changed')
        require(r['mutation_checked']==str(native).upper(),'Missing-count mutation was not checked')
        for field in HASHES+(('cleared_hash',) if native else ()):
            require(len(r[field])==64 and set(r[field])<=set('0123456789abcdef'),'Malformed full hash')
        if not native:require(r['cleared_hash']=='','Bare result has a native cache claim')
def validate_all(rows,rounds,phase):
    require(len(rows)==2*rounds*len(cases()),'Observation count')
    rebuilt=[]
    for number in range(1,rounds+1):
        for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            group=[r for r in rows if r['variant']==variant and integer(r['round'])==number]
            validate_round(group,number,phase);rebuilt.extend(group)
    require(rebuilt==rows,'Build order changed')
    for r in rows:
        candidate=r['variant']=='candidate'
        require(integer(r['domain_available'])==int(candidate),'Wrong diagnostic availability')
        require(integer(r['long_domain_before'])==0,'Long input has FLOAT fact')
        require(integer(r['float_domain_before'])==0,'Imported FLOAT unexpectedly trusted')
    for case in cases():
        selected=[r for r in rows if tuple(r[k] for k in FIELDS)==case]
        require(len({tuple(r[k] for k in RESULT_FIELDS) for r in selected})==1,'Per-case source/result evidence changed')
        if phase=='measure':
            width=len(representations(case[1]))
            for variant in ('baseline','candidate'):
                require(Counter(integer(r['position']) for r in selected if r['variant']==variant)==Counter({p:rounds//width for p in range(1,width+1)}),'Unbalanced representation order')
    for pattern in PANELS['plain']:
        selected=[r for r in rows if r['pattern']==pattern]
        shared=('input_hash','rank_hash','result_hash','missing_hash')+SEMANTICS
        require(len({tuple(r[k] for k in shared) for r in selected})==1,'Equivalent inputs/outputs differ across layouts, order or representation')
        native=[r for r in selected if r['representation']!='ordinary']
        require(len({r['cleared_hash'] for r in native})==1,'Cleared result differs across equivalent cases')
def summarize(rows):
    result=[]
    for layout,patterns in PANELS.items():
        for pattern,operation in itertools.product(patterns,OPERATIONS):
            row=dict(layout=layout,pattern=pattern,operation=operation)
            groups={(variant,rep):sorted([r for r in rows if (r['layout'],r['pattern'],r['operation'],r['variant'],r['representation'])==(layout,pattern,operation,variant,rep)],key=lambda r:integer(r['round'])) for variant in ('baseline','candidate') for rep in representations(pattern)}
            for (variant,rep),group in groups.items():
                for metric in ('cpu','wall'):
                    row[f'{variant}_{rep}_{metric}']=statistics.median(float(r[metric])/integer(r['repetitions']) for r in group)
            for rep in representations(pattern):
                for metric in ('cpu','wall'):
                    row[f'{rep}_{metric}_speedup']=row[f'baseline_{rep}_{metric}']/row[f'candidate_{rep}_{metric}']
                    row[f'{rep}_{metric}_paired_speedup']=statistics.median((float(b[metric])/integer(b['repetitions']))/(float(c[metric])/integer(c['repetitions'])) for b,c in zip(groups['baseline',rep],groups['candidate',rep]))
            for variant in ('baseline','candidate'):
                row[f'{variant}_compact_typed_cpu']=row[f'{variant}_compact_cpu']/row[f'{variant}_typed_double_cpu']
                if 'ordinary' in representations(pattern):row[f'{variant}_compact_ordinary_cpu']=row[f'{variant}_compact_cpu']/row[f'{variant}_ordinary_cpu']
            result.append(row)
    return result

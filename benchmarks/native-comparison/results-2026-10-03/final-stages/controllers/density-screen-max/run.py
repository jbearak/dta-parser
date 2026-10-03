#!/usr/bin/env python3
"""Private dense-missing guard: exact vectorized float pairs versus threshold pairs."""
import argparse
from collections import Counter
import csv
from decimal import Decimal, InvalidOperation
import difflib
import hashlib
import importlib.util
import itertools
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

HERE=Path(__file__).resolve().parent
DENSITIES=('random_half','clustered_half','all_tags')
OPERATIONS=('pair_less','pair_equal')
REPRESENTATIONS=('compact','typed_double')
FIELDS=('density','operation','representation')
CASES=set(itertools.product(DENSITIES,OPERATIONS,REPRESENTATIONS))
HASHES=('result_hash','input_hash','y_hash','metadata_x','metadata_y','rank_x_hash','rank_y_hash')
STATES=('compact_before','materialized_before','y_compact_before','y_materialized_before')
RESULT_FIELDS=HASHES+STATES+('x_missing','y_missing','pair_missing')
COMMITS={'baseline':'e36e50c23dfbb39eabc94cf4252ec29f3db3d5eb',
         'candidate':'deaa84e794a587cdc507cb9456f25b42dd03eb6c'}

def require(ok,message):
    if not ok:raise RuntimeError(message)

def integer(value):
    try:d=Decimal(str(value))
    except InvalidOperation:raise RuntimeError('Invalid integer')
    require(d.is_finite() and d>=0 and d==d.to_integral_value(),'Invalid integer')
    return int(d)

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path,value):path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')

def write_csv(path,rows):
    with path.open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=tuple(rows[0]));writer.writeheader();writer.writerows(rows)

def read_csv(path):
    with path.open(newline='') as stream:return list(csv.DictReader(stream))

def order(number):
    densities=tuple(itertools.permutations(DENSITIES))[(number-1)%6]
    operations=OPERATIONS if number%2 else tuple(reversed(OPERATIONS))
    result=[]
    for dp,density in enumerate(densities,1):
        for op,operation in enumerate(operations,1):
            case=DENSITIES.index(density)*2+OPERATIONS.index(operation)+1
            reps=REPRESENTATIONS if (number+case)%2 else tuple(reversed(REPRESENTATIONS))
            for rp,representation in enumerate(reps,1):
                result.append((density,operation,representation,dp,op,rp))
    return result

def validate_round(rows,number,phase):
    require(Counter(tuple(r[k] for k in FIELDS) for r in rows)==Counter({k:1 for k in CASES}),'Incomplete or repeated case matrix')
    require([(r['density'],r['operation'],r['representation'],integer(r['density_position']),
              integer(r['operation_position']),integer(r['position'])) for r in rows]==order(number),'Execution order changed')
    for row in rows:
        require(integer(row['round'])==number and row['threads']=='1' and integer(row['rows'])==1000000 and integer(row['repetitions'])>0,'Wrong round/threads/shape/repetitions')
        require(row['phase']==phase,'Wrong worker phase')
        for metric in ('cpu','wall'):
            value=float(row[metric]);require(math.isfinite(value) and (value>0 if phase=='measure' else value==0),'Invalid timing interval')
        expected=1000000 if row['density']=='all_tags' else 500000
        require(integer(row['x_missing'])==integer(row['y_missing'])==expected,'Wrong marginal missing counts')
        pair=integer(row['pair_missing'])
        require((500000<=pair<=1000000) if row['density']=='random_half' else pair==expected,'Wrong joint missing count')
        for prefix in ('compact','materialized','y_compact','y_materialized'):
            require(row[prefix+'_before']==row[prefix+'_after'],'Source representation changed')
        compact=str(row['representation']=='compact').upper()
        require(row['compact_before']==row['y_compact_before']==compact and row['materialized_before']==row['y_materialized_before']=='FALSE','Wrong source representation')
        require(row['native_qualified']=='TRUE','Native path not qualified')
        for field in HASHES:require(len(row[field])==64 and set(row[field])<=set('0123456789abcdef'),'Malformed full hash')

def validate_all(rows,rounds,phase):
    require(len(rows)==2*rounds*len(CASES),'Observation count')
    rebuilt=[]
    for number in range(1,rounds+1):
        for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            group=[r for r in rows if r['variant']==variant and integer(r['round'])==number]
            validate_round(group,number,phase);rebuilt.extend(group)
    require(rebuilt==rows,'Build execution order changed')
    for case in CASES:
        selected=[r for r in rows if tuple(r[k] for k in FIELDS)==case]
        require(len({tuple(r[k] for k in RESULT_FIELDS) for r in selected})==1,'Source/result/metadata changed across builds or rounds')
        if phase=='measure':
            for variant in ('baseline','candidate'):
                require(Counter(integer(r['position']) for r in selected if r['variant']==variant)==Counter({1:rounds//2,2:rounds//2}),'Unbalanced representation order')
    for density,operation in itertools.product(DENSITIES,OPERATIONS):
        selected=[r for r in rows if r['density']==density and r['operation']==operation]
        require(len({tuple(r[k] for k in ('result_hash','input_hash','y_hash','rank_x_hash','rank_y_hash','x_missing','y_missing','pair_missing')) for r in selected})==1,'Equivalent representations disagree')
    if phase=='measure':
        for variant in ('baseline','candidate'):
            observed=[]
            for number in range(1,rounds+1):
                group=[r for r in rows if r['variant']==variant and integer(r['round'])==number]
                observed.append(tuple(dict.fromkeys(r['density'] for r in group)))
            require(Counter(observed)==Counter({p:rounds//6 for p in itertools.permutations(DENSITIES)}),'Unbalanced density permutations')

def summarize(rows):
    result=[]
    for density,operation in itertools.product(DENSITIES,OPERATIONS):
        record=dict(density=density,operation=operation)
        selected={variant:{rep:sorted([r for r in rows if r['variant']==variant and r['density']==density and r['operation']==operation and r['representation']==rep],key=lambda r:integer(r['round'])) for rep in REPRESENTATIONS} for variant in ('baseline','candidate')}
        for variant in selected:
            for rep in REPRESENTATIONS:
                for metric in ('cpu','wall'):
                    record[f'{variant}_{rep}_{metric}']=statistics.median(float(r[metric])/integer(r['repetitions']) for r in selected[variant][rep])
            record[variant+'_compact_typed_cpu']=record[variant+'_compact_cpu']/record[variant+'_typed_double_cpu']
        for rep in REPRESENTATIONS:
            for metric in ('cpu','wall'):
                record[f'{rep}_{metric}_speedup']=record[f'baseline_{rep}_{metric}']/record[f'candidate_{rep}_{metric}']
                record[f'{rep}_{metric}_paired_median_speedup']=statistics.median((float(b[metric])/integer(b['repetitions']))/(float(c[metric])/integer(c['repetitions'])) for b,c in zip(selected['baseline'][rep],selected['candidate'][rep]))
        result.append(record)
    return result

def inventory(build,role,repository):
    path=repository/'benchmarks/native-operations/run.py'
    spec=importlib.util.spec_from_file_location('density_build_validator',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    receipt=json.loads((build/'build-receipt.json').read_text())
    result=module.inventory(build,receipt['variant'])
    require(result['receipt']['base_commit']==COMMITS[role],'Wrong measured source revision')
    require(result['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'Unexpected measured-source patch')
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('baseline','candidate','repository','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--rounds',type=int,default=6)
    parser.add_argument('--qualify-only',action='store_true')
    parser.add_argument('--qualification',type=Path)
    args=parser.parse_args();phase='qualify' if args.qualify_only else 'measure';rounds=1 if args.qualify_only else args.rounds
    if not args.qualify_only and (rounds<6 or rounds%6):parser.error('Use a positive multiple of six rounds')
    if not args.qualify_only and args.qualification is None:parser.error('Completed identical-bound qualification is required')
    found=shutil.which('Rscript');require(found is not None,'Rscript absent');launcher=Path(found).resolve(strict=True)
    repository=args.repository.resolve();builds={v:getattr(args,v).resolve() for v in ('baseline','candidate')};out=args.output.resolve()
    controllers={'density_controller':Path(__file__).resolve(),'density_worker':HERE/'worker.R',
        'build_validation':repository/'benchmarks/native-operations/run.py',
        'build_recorder':repository/'benchmarks/r-file-readers/record-builds.py',
        'build_recorder_parent':repository/'benchmarks/io-optimization/record-builds.py'}
    def binding():
        details=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(),"\\n",R.version.string,sep="")'],text=True).splitlines()
        execution=dict(Rscript=str(launcher),Rscript_sha256=digest(launcher),R_runtime_sha256=digest(Path(details[0])/'bin/exec/R'),R_version=details[1])
        results={v:inventory(b,v,repository) for v,b in builds.items()}
        require(all(b['receipt']['toolchain']['R_runtime_sha256']==execution['R_runtime_sha256'] for b in results.values()),'Build/execution runtime mismatch')
        return dict(builds=results,execution=execution,controllers={k:digest(p) for k,p in controllers.items()})
    before=binding();out.mkdir(parents=True,exist_ok=False);write_json(out/'provenance-before.json',before)
    if phase=='measure':
        q=json.loads((args.qualification/'completion.json').read_text())
        require(q['phase']=='qualify' and q['exact_results'] is True,'Missing successful qualification')
        require(json.loads((args.qualification/'provenance-after.json').read_text())==before,'Qualification binding changed')
        for name,sha in q['artifacts'].items():require(digest(args.qualification/name)==sha,'Qualification artifact changed')
    patch=[]
    for name in sorted(set(before['builds']['baseline']['source'])|set(before['builds']['candidate']['source'])):
        if before['builds']['baseline']['source'].get(name)==before['builds']['candidate']['source'].get(name):continue
        a=builds['baseline']/'source'/name;b=builds['candidate']/'source'/name
        patch.extend(difflib.unified_diff(a.read_text().splitlines(keepends=True) if a.exists() else [],b.read_text().splitlines(keepends=True) if b.exists() else [],fromfile='a/'+name,tofile='b/'+name))
    (out/'source.patch').write_text(''.join(patch))
    write_json(out/'protocol.json',dict(phase=phase,rounds=rounds,cases_per_build_round=len(CASES),host=platform.platform(),machine=platform.machine(),logical_cpus=os.cpu_count(),
        input='One million retained float values, X spans8191 and Y spans16385; matching typed-double controls. Independently sampled exact50% missing per input, same contiguous first-half missing in both inputs, or100% missing. All27 missing ranks present in each column. Finite values are exactly binary32-representable. Fixed documented RNG seeds.',
        order='Six density permutations; alternating operation and build order. Each representation occupies each position three times over six rounds. Fresh R process per build/round.',
        oracle='Full independent integer-rank logical oracle; complete input/result/rank/metadata hashes and retained states before/after; separate native eligibility qualification.',
        interval='Repeated public calls include output allocation and automatic GC. Construction, explicit GC, calibration, full hashes and native eligibility checks excluded. Calibration>=50ms then target300ms aggregate CPU.',
        limits='One host, fixed warm constructed span geometry, modern canonical missing codes, threads1 only. The randomized/clustered cases have different joint missing rates; this is not an isolated branch-prediction experiment. Native eligibility is not a per-timed-call entry counter. No arbitrary import, temporal, reader or universal density claim.'))
    rows=[]
    for number in range(1,rounds+1):
        for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            output=out/f'{number:02}-{variant}.csv'
            command=[str(launcher),'--vanilla',str(HERE/'worker.R'),str(builds[variant]/'library'),str(number),str(output)]
            if args.qualify_only:command.append('qualify')
            with (out/f'{number:02}-{variant}.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
            batch=read_csv(output);validate_round(batch,number,phase);rows.extend(dict(variant=variant,**r) for r in batch)
            print(f'Completed {number} {variant}',flush=True)
    validate_all(rows,rounds,phase);write_csv(out/'raw.csv',rows)
    if phase=='measure':write_csv(out/'summary.csv',summarize(rows))
    after=binding();require(before==after,'Source/runtime/controller changed');write_json(out/'provenance-after.json',after)
    artifacts={p.name:digest(p) for p in out.iterdir() if p.suffix in ('.csv','.json','.patch')}
    write_json(out/'completion.json',dict(phase=phase,observations=len(rows),rounds=rounds,exact_results=True,provenance_unchanged=True,artifacts=artifacts))
    print(f'Complete: {len(rows)} qualified {phase} observations')

if __name__=='__main__':main()

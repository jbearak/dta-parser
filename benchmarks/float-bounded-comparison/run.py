#!/usr/bin/env python3
"""Private three-panel compact-float bounded-fallback screen."""
import argparse
import csv
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

from core import PANELS, cases, require, validate_round, validate_all, summarize

HERE=Path(__file__).resolve().parent
COMMITS={'baseline':'bb135c1f274e0ddb5d37d29fdccdcf34b09f83f2',
         'candidate':'847919ceb78bf08674fca9f9af02583449e590a6'}

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write_json(path,value):path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def write_csv(path,rows):
    with path.open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=tuple(rows[0]));writer.writeheader();writer.writerows(rows)
def read_csv(path):
    with path.open(newline='') as stream:return list(csv.DictReader(stream))

def inventory(build,role,repository):
    path=repository/'benchmarks/native-operations/run.py'
    spec=importlib.util.spec_from_file_location('float_bounded_build_validator',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    receipt=json.loads((build/'build-receipt.json').read_text())
    result=module.inventory(build,receipt['variant'])
    require(result['receipt']['base_commit']==COMMITS[role],'Wrong measured source revision')
    require(result['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'Unexpected measured-source patch')
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('baseline','candidate','repository','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--panel',choices=tuple(PANELS),required=True)
    parser.add_argument('--rounds',type=int,default=6)
    parser.add_argument('--qualify-only',action='store_true')
    parser.add_argument('--qualification',type=Path)
    args=parser.parse_args();phase='qualify' if args.qualify_only else 'measure';rounds=1 if args.qualify_only else args.rounds
    if not args.qualify_only and (rounds<6 or rounds%6):parser.error('Use a positive multiple of six rounds')
    if not args.qualify_only and args.qualification is None:parser.error('Completed identical-bound qualification is required')
    require(os.name!='nt','This benchmark requires the Unix R executable layout')
    found=shutil.which('Rscript');require(found is not None,'Rscript absent');launcher=Path(found).resolve(strict=True)
    repository=args.repository.resolve();builds={v:getattr(args,v).resolve() for v in ('baseline','candidate')};out=args.output.resolve()
    controllers={'controller':Path(__file__).resolve(),'worker':HERE/'worker.R','validation':HERE/'core.py','protocol_tests':HERE/'test-run.py',
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
        require(q['phase']=='qualify' and q['exact_results'] is True and q['panel']==args.panel,'Missing successful qualification')
        require(json.loads((args.qualification/'provenance-after.json').read_text())==before,'Qualification binding changed')
        for name,sha in q['artifacts'].items():require(digest(args.qualification/name)==sha,'Qualification artifact changed')
    patch=[]
    for name in sorted(set(before['builds']['baseline']['source'])|set(before['builds']['candidate']['source'])):
        if before['builds']['baseline']['source'].get(name)==before['builds']['candidate']['source'].get(name):continue
        a=builds['baseline']/'source'/name;b=builds['candidate']/'source'/name
        patch.extend(difflib.unified_diff(a.read_text().splitlines(keepends=True) if a.exists() else [],b.read_text().splitlines(keepends=True) if b.exists() else [],fromfile='a/'+name,tofile='b/'+name))
    (out/'source.patch').write_text(''.join(patch))
    write_json(out/'protocol.json',dict(phase=phase,panel=args.panel,rounds=rounds,cases_per_build_round=len(cases(args.panel)),host=platform.platform(),machine=platform.machine(),logical_cpus=os.cpu_count(),
        input='One million identical values per layout. Plain compact float spans and retained float spans8191/16385 are targets; contiguous typed-double pairs are unchanged runtime controls. Density panel: independent exact50% missing per input, same first-half missing, and100% missing. Pattern panel: matched first256/last256/alternating64-row missing runs. Ordinary panel: no missing and sparse independent997/991-row grids. All27 canonical missing ranks cycle forward in X/backward in Y where present; finite values are exactly binary32-representable.',
        order=('One unclocked qualification round, baseline then candidate, fresh R process for each.' if phase=='qualify' else 'Six complete permutations for each3-pattern panel; alternating2-pattern order in ordinary panel. Build, operation, layout and representation orders alternate; each layout/representation occupies each position three times. Fresh R process per build/round.'),
        oracle='Full independent integer-rank logical oracle; complete input/result/rank/metadata hashes and compact/materialized/retained/chunk states before/after. Identical values and ranks across layouts. Separate native eligibility check.',
        interval=('No clocks or calibration. One recorded comparison repetition preceded by public-result and native-eligibility checks, with complete validation.' if phase=='qualify' else 'Repeated public calls include output allocation and automatic GC. Construction, explicit GC, calibration, hashes and native checks excluded. Calibration>=50ms then target300ms aggregate CPU.'),
        limits='One host, warm constructed inputs, modern canonical missing codes, threads1, one retained chunk geometry. Plain compact targets and all typed-double controls reach full contiguous1m spans. Patterns differ in marginal/joint density and run lengths; cross-pattern ratios do not isolate branch prediction. Native eligibility is not a per-timed-call entry count. No reader/decompression, temporal, arbitrary import or universal speed claim.'))
    rows=[]
    for number in range(1,rounds+1):
        for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
            output=out/f'{number:02}-{variant}.csv'
            command=[str(launcher),'--vanilla',str(HERE/'worker.R'),str(builds[variant]/'library'),str(number),str(output),args.panel]
            if args.qualify_only:command.append('qualify')
            with (out/f'{number:02}-{variant}.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
            batch=read_csv(output);validate_round(batch,number,phase,args.panel);rows.extend(dict(variant=variant,**r) for r in batch)
            print(f'Completed {number} {variant}',flush=True)
    validate_all(rows,rounds,phase,args.panel);write_csv(out/'raw.csv',rows)
    if phase=='measure':write_csv(out/'summary.csv',summarize(rows,args.panel))
    after=binding();require(before==after,'Source/runtime/controller changed');write_json(out/'provenance-after.json',after)
    artifacts={p.name:digest(p) for p in out.iterdir() if p.suffix in ('.csv','.json','.patch')}
    write_json(out/'completion.json',dict(phase=phase,panel=args.panel,observations=len(rows),rounds=rounds,exact_results=True,provenance_unchanged=True,artifacts=artifacts))
    print(f'Complete: {len(rows)} qualified {phase} observations')

if __name__=='__main__':main()

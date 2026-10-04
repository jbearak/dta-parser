#!/usr/bin/env python3
"""Actual-header work counts, with independent values and mocked R boundaries.

No package files are edited. Every consumed source is checked against the
requested immutable Git tree before and after the private compilation/run.
"""
import argparse
import csv
from collections import Counter
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
DEFAULT_ROOT=HERE.parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def require(value,message):
    if not value:raise RuntimeError(message)
def function(text,name):
    declaration=text.index(name+'(')
    start=text.rfind('static ',0,declaration)
    opening=text.index('{',declaration)
    depth=1;end=opening+1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]
def replace_once(text,old,new):
    require(text.count(old)==1,'Instrumentation site is not unique: '+old)
    return text.replace(old,new)
def inventory(root,commit):
    require(re.fullmatch(r'[0-9a-f]{40}',commit) is not None,'Expected a full immutable source commit')
    git_env={key:value for key,value in os.environ.items() if not key.startswith('GIT_')}
    src=root/'r-package/dtatools/src'
    paths=sorted(src.glob('numeric-arithmetic*.h'))+[src/'numeric-payload.c',src/'dtatools-internal.h']
    result={}
    for path in paths:
        original=subprocess.check_output(['git','--no-replace-objects','show',commit+':r-package/dtatools/src/'+path.name],cwd=root,env=git_env)
        digest=sha(path)
        require(hashlib.sha256(original).hexdigest()==digest,'Source differs from immutable commit: '+path.name)
        result[path.name]=digest
    return result

def expected_cases():
    result=[]
    def add(n,p,lx,ly,xc,yc,reverse):result.append((n,p,lx,ly,xc,yc,reverse))
    for reverse in range(2):
        for pattern in ('ordinary','sparse','prefix256','suffix256','random_half','all_tags'):
            add(1000000,pattern,0,0,0,0,reverse)
    for reverse in range(2):
        for pattern in ('ordinary','sparse','prefix256'):
            add(1000000,pattern,0,0,8191,16385,reverse)
    for lx in range(2):
        for ly in range(2):
            for reverse in range(2):
                add(369,'edges',lx,ly,7,11,reverse)
                for n in (2,63,64,65,255,256,257,16383,16384,16385,32767,32768,32769):
                    add(n,'alternating64',lx,ly,7,11,reverse)
    for reverse in range(2):
        for xc,yc in ((8191,16385),(7,11)):add(1000000,'all_tags',0,0,xc,yc,reverse)
        for pattern in ('all_long_missing','all_float_missing'):
            for xc,yc in ((0,0),(8191,16385),(7,11)):add(1000000,pattern,0,0,xc,yc,reverse)
            for lx in range(2):
                for ly in range(2):add(128,pattern,lx,ly,7,11,reverse)
    return result

def validate_rows(rows):
    fields=('length','pattern','legacy_long','legacy_float','long_chunk','float_chunk','reverse')
    actual=[tuple(r[k] if k=='pattern' else int(r[k]) for k in fields) for r in rows]
    require(Counter(actual)==Counter(expected_cases()),'Incomplete or duplicated probe matrix')
    require(actual==expected_cases(),'Probe execution order changed')
    for r in rows:
        for k,v in r.items():
            if k!='pattern':require(re.fullmatch(r'[0-9]+',v) is not None,'Malformed numeric record')
        n=int(r['length']);pattern=r['pattern']
        require(int(r['semantic_error']) in range(5),'Invalid semantic status')
        require(int(r['output'])==4 and int(r['allocations'])==1,'Unexpected output or allocation')
        require(int(r['result_missing'])==int(r['stored_missing'])<=n,'Missing count mismatch')
        xm=int(r['input_long_missing']);ym=int(r['input_float_missing']);overlap=int(r['overlap'])
        require(0<=overlap<=min(xm,ym)<=max(xm,ym)<=n,'Invalid input missing counts')
        all_missing=xm==n or ym==n
        expected_all=pattern in ('all_tags','all_long_missing','all_float_missing') or (pattern=='alternating64' and n<=64)
        require(all_missing==expected_all and int(r['all_missing_gate'])==int(all_missing),'All-missing admission changed')
        require(not all_missing or int(r['result_missing'])==n,'All-missing result incomplete')
        trusted=r['legacy_float']=='0' and pattern not in ('edges','all_long_missing')
        require(int(r['canonical_fact'])==int(trusted),'Canonical fixture admission changed')
        gated=n==1000000 and pattern in ('ordinary','sparse','prefix256','suffix256')
        bound=0 if pattern=='ordinary' else n//5 if pattern=='sparse' else n//10
        canonical_work=trusted and (int(r['exact_float_rows']) != 0 or (gated and int(r['canonical_rows'])>bound))
        require(int(r['canonical_work_failure'])==int(canonical_work),'Canonical work ledger mismatch')
        work=all_missing and any(int(r[k]) for k in ('exact_float_rows','exact_integer_rows','proof_rows','canonical_rows','source_span_rows'))
        require(int(r['all_missing_work_failure'])==int(work),'Work failure record inconsistent')
        gated=n==1000000 and pattern in ('ordinary','sparse','prefix256','suffix256')
        bound=0 if pattern=='ordinary' else n//5 if pattern=='sparse' else n//10
        require(int(r['work_gate'])==int(gated) and int(r['work_bound'])==bound,'Original work gate changed')
    return sum(int(r['semantic_error'])!=0 for r in rows),sum(r['canonical_work_failure']=='1' or (r['work_gate']=='1' and int(r['exact_float_rows'])>int(r['work_bound'])) or r['all_missing_work_failure']=='1' for r in rows)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--root',type=Path,default=DEFAULT_ROOT)
    parser.add_argument('--commit', help='Full source commit; defaults to the current checkout HEAD')
    parser.add_argument('--require-proved',action='store_true')
    args=parser.parse_args();root=args.root.resolve();src=root/'r-package/dtatools/src'
    if args.commit is None:
        git_env={key:value for key,value in os.environ.items() if not key.startswith('GIT_')}
        args.commit=subprocess.check_output(['git','--no-replace-objects','rev-parse','HEAD'],cwd=root,env=git_env,text=True).strip()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    sources=inventory(root,args.commit)
    controller_before=sha(Path(__file__));probe_before=sha(HERE/'work-count.c')
    for name in sources:
        if name.endswith('.h'):(output/name).write_bytes((src/name).read_bytes())
    payload=(src/'numeric-payload.c').read_text();arithmetic=(src/'numeric-arithmetic.h').read_text()
    begin=arithmetic.index('typedef struct {\n    double minimum;')
    end=arithmetic.index('/* Missing-bearing same-width',begin)
    common=arithmetic[begin:end]
    common+='\n'+function((src/'dtatools-internal.h').read_text(),'numeric_strict_modern_float')
    common+='\n'+function(arithmetic,'arithmetic_promoted_kind')
    common+='\n'+function(payload,'numeric_float_observed_limit')
    common+='\n'+function(payload,'scalar_arithmetic_result_valid').replace('scalar_arithmetic_result_valid','uncounted_result_valid')
    common+='\nstatic int scalar_arithmetic_result_valid(double value) { result_checks[phase]++; return uncounted_result_valid(value); }\n'
    common+='\n'+function((src/'numeric-arithmetic-integer.h').read_text(),'arithmetic_integer_missing')
    for name in ('arithmetic_scale_float_invalid_modern','arithmetic_scale_float_invalid_legacy'):
        common+='\n'+function((src/'numeric-arithmetic-scale.h').read_text(),name)
    (output/'production-common.h').write_text(common)
    general_path=output/'numeric-arithmetic-general.h';general=general_path.read_text()
    general=replace_once(general,'            double xv = arithmetic_general_load_##X',
        '            general_rows[phase]++;                              \\\n            double xv = arithmetic_general_load_##X')
    general_path.write_text(general)
    pair_path=output/'numeric-arithmetic-pair.h';pair=pair_path.read_text()
    pair=replace_once(pair,'        TYPE value;',
        '        exact_integer_rows++;                                      \\\n        TYPE value;')
    pair=replace_once(pair,'        (void) policy;',
        '        exact_float_rows++;                                       \\\n        (void) policy;')
    pair_path.write_text(pair)
    specialized_path=output/'numeric-arithmetic-pair-long-float.h'
    specialized=replace_once(specialized_path.read_text(),
        '    int32_t integer_maximum = INT32_MIN;',
        '    proof_rows += count;\n    int32_t integer_maximum = INT32_MIN;')
    specialized=replace_once(specialized,
        '    size_t start, size_t count, int observed, arithmetic_general_output *output\n) {',
        '    size_t start, size_t count, int observed, arithmetic_general_output *output\n) {\n    canonical_rows += count;')
    specialized_path.write_text(specialized)
    compiler_path=shutil.which('cc')
    require(compiler_path is not None, 'C compiler cc is required for the current-source work probe')
    compiler=Path(compiler_path).resolve();compiler_before=sha(compiler)
    executable=output/'work-count'
    command=[str(compiler),'-std=c11','-O1','-Wall','-Wextra','-Werror','-Wno-unused-function',
        '-I',str(output),str(HERE/'work-count.c'),'-lm','-o',str(executable)]
    with (output/'compile.log').open('w') as log:
        compiled=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,cwd=output)
    require(compiled.returncode==0,'Compilation failed; see compile.log')
    run_command=[str(executable)]+(['require-proved'] if args.require_proved else [])
    run=subprocess.run(run_command,text=True,capture_output=True,cwd=output)
    (output/'work-count.csv').write_text(run.stdout);(output/'work-count.log').write_text(run.stderr)
    require(sources==inventory(root,args.commit),'Source changed during qualification')
    require(sha(compiler)==compiler_before and sha(Path(__file__))==controller_before and sha(HERE/'work-count.c')==probe_before,'Compiler/controller changed')
    rows=list(csv.DictReader(io.StringIO(run.stdout)))
    semantic_failures,work_failures=validate_rows(rows)
    reported_work=work_failures if args.require_proved else 0
    expected_summary=f"{'FAIL' if semantic_failures or reported_work else 'PASS'}: {semantic_failures} semantic failures, {reported_work} proved-work failures across {len(rows)} cases\n"
    require(run.stderr==expected_summary,'Probe summary does not match complete records')
    expected_code=1 if semantic_failures or (args.require_proved and work_failures) else 0
    require(run.returncode==expected_code,'Probe exit status does not match semantic/work records')
    record=dict(commit=args.commit,root=str(root),source_sha256=sources,source_before_after_equal=True,
        controller_sha256=controller_before,probe_sha256=probe_before,compiler_sha256=compiler_before,
        compiler_version=subprocess.check_output([str(compiler),'--version'],text=True),command=command,run_command=run_command,cwd=str(output),
        require_proved=args.require_proved,exit_code=run.returncode,cases=len(rows),semantic_failures=semantic_failures,work_failures=work_failures,
        artifact_sha256={p.name:sha(p) for p in output.iterdir() if p.is_file()},
        scope='Actual production result/preflight/pair-producer headers with counters in private copies. Independent bit/classification oracle. Mocked R allocation, span, interrupt and publication boundaries: no ownership/reentry, public missing-cache mutation, performance or compiler-codegen claim.')
    (output/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
    print(run.stderr,end='');print('Receipt:',output/'receipt.json')
    raise SystemExit(run.returncode)
if __name__=='__main__':main()

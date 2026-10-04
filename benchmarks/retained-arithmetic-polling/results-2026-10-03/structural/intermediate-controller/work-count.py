#!/usr/bin/env python3
"""Actual-header work counts, with independent values and mocked R boundaries.

No package files are edited. Every consumed source is checked against the
requested immutable Git tree before and after the private compilation/run.
"""
import argparse
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
DEFAULT_ROOT=Path('<private-work>/dta-retained-span-work')
DEFAULT_COMMIT='387227cdb8a174feccb24e5f52745177c5af3f95'
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
    paths=sorted(src.glob('numeric-arithmetic*.h'))+[src/'numeric-payload.c']
    result={}
    for path in paths:
        original=subprocess.check_output(['git','--no-replace-objects','show',commit+':r-package/dtatools/src/'+path.name],cwd=root,env=git_env)
        digest=sha(path)
        require(hashlib.sha256(original).hexdigest()==digest,'Source differs from immutable commit: '+path.name)
        result[path.name]=digest
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--root',type=Path,default=DEFAULT_ROOT)
    parser.add_argument('--commit',default=DEFAULT_COMMIT)
    parser.add_argument('--require-proved',action='store_true')
    args=parser.parse_args();root=args.root.resolve();src=root/'r-package/dtatools/src'
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    sources=inventory(root,args.commit)
    controller_before=sha(Path(__file__));probe_before=sha(HERE/'work-count.c')
    for name in sources:
        if name.endswith('.h'):(output/name).write_bytes((src/name).read_bytes())
    payload=(src/'numeric-payload.c').read_text();arithmetic=(src/'numeric-arithmetic.h').read_text()
    begin=arithmetic.index('typedef struct {\n    double minimum;')
    end=arithmetic.index('/* Missing-bearing same-width',begin)
    common=arithmetic[begin:end]
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
    compiler=Path(shutil.which('cc')).resolve();compiler_before=sha(compiler)
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
    expected={(1000000,p,x,y,r) for p in ('ordinary','sparse') for x,y in ((0,0),(8191,16385),(7,11)) for r in (0,1)}
    expected|={(n,'ordinary',7,11,r) for n in (16383,16384,16385) for r in (0,1)}
    actual=[(int(r['length']),r['pattern'],int(r['long_chunk']),int(r['float_chunk']),int(r['reverse'])) for r in rows]
    require(len(rows)==18 and len(set(actual))==18 and set(actual)==expected,'Incomplete probe matrix')
    semantic_failures=sum(int(row['semantic_error'])!=0 for row in rows)
    work_failures=sum(int(row['interrupt_calls'])>int(row['work_bound']) for row in rows)
    expected_code=1 if semantic_failures or (args.require_proved and work_failures) else 0
    require(run.returncode==expected_code,'Probe exit status does not match semantic/work records')
    record=dict(commit=args.commit,root=str(root),source_sha256=sources,source_before_after_equal=True,
        controller_sha256=controller_before,probe_sha256=probe_before,compiler_sha256=compiler_before,
        compiler_version=subprocess.check_output([str(compiler),'--version'],text=True),command=command,run_command=run_command,cwd=str(output),
        require_proved=args.require_proved,exit_code=run.returncode,cases=len(rows),semantic_failures=semantic_failures,work_failures=work_failures,
        artifact_sha256={p.name:sha(p) for p in output.iterdir() if p.is_file()},
        scope='Actual production result/preflight/pair-producer headers. Independent bit/classification oracle; counts interrupt and span-boundary calls, with exact requested/returned row trace digest. Span lookup and R interrupt work remain mocked. No ownership/reentry, real Rust search-comparison, public cached-count mutation, performance or compiler-codegen claim.')
    (output/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
    print(run.stderr,end='');print('Receipt:',output/'receipt.json')
    raise SystemExit(run.returncode)
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Bind focused external test source separately from the installed runtime."""
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE=Path(__file__).resolve().parent
RECORDER=Path('<recorder_repository>/benchmarks/native-operations/run.py')
def need(condition,message):
    if not condition:raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write(path,data):path.write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
def runtime(launcher):
    result=subprocess.check_output([str(launcher),'--vanilla','-e',
        'cat(R.home(), R.version.string, sep=intToUtf8(10L))'],text=True)
    home,version=result.splitlines()
    return dict(launcher=str(launcher),launcher_sha256=sha(launcher),R_home=home,
        R_version=version,R_runtime_sha256=sha(Path(home)/'bin/exec/R'))
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--build',type=Path,required=True)
    parser.add_argument('--source-root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();build=args.build.resolve();repo=args.source_root.resolve();output=args.output.resolve()
    output.mkdir(parents=True,exist_ok=False)
    tests=repo/'r-package/dtatools/tests/testthat'
    spec=importlib.util.spec_from_file_location('records',RECORDER);records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
    launcher=Path(shutil.which('Rscript')).resolve(strict=True)
    receipt=json.loads((build/'build-receipt.json').read_text())
    git_env={key:value for key,value in os.environ.items() if not key.startswith('GIT_')}
    def git(*parts):
        return subprocess.check_output(['git','--no-replace-objects',*parts],cwd=repo,env=git_env)
    def bind():
        bound=records.inventory(build,receipt['variant'])
        rt=runtime(launcher)
        need(rt['R_runtime_sha256']==bound['receipt']['toolchain']['R_runtime_sha256'],'Worker/build runtime differs')
        # External test files intentionally differ from the older baseline's
        # installed tests. Bind every helper/fixture/test and the source delta.
        source={str(p.relative_to(tests.parent)):sha(p) for p in tests.parent.rglob('*') if p.is_file()}
        patch=git('diff','HEAD','--','r-package/dtatools/tests')
        return dict(build=bound,runtime=rt,tests=source,test_source_head=git('rev-parse','HEAD').decode().strip(),
            test_source_patch_sha256=hashlib.sha256(patch).hexdigest(),
            controllers={p.name:sha(p) for p in (Path(__file__).resolve(),HERE/'focused.R',RECORDER)})
    before=bind();write(output/'before.json',before)
    patch=git('diff','HEAD','--','r-package/dtatools/tests')
    (output/'test-source.patch').write_bytes(patch)
    command=[str(launcher),'--vanilla',str(HERE/'focused.R'),str(build/'library'),str(tests),str(output/'focused.csv')]
    launch=dict(command=command,cwd=str(repo),started_utc=datetime.now(timezone.utc).isoformat(),scope='Public focused correctness with full external test-tree and installed-runtime binding; no performance measurement.')
    write(output/'command.json',launch)
    with (output/'focused.log').open('w') as log:run=subprocess.run(command,cwd=repo,stdout=log,stderr=subprocess.STDOUT)
    after=bind();write(output/'after.json',after);need(before==after,'Qualification inputs changed')
    launch.update(exit_code=run.returncode,finished_utc=datetime.now(timezone.utc).isoformat());write(output/'command.json',launch)
    need(run.returncode==0,'Focused R tests failed; preserved log/CSV')
    rows=list(csv.DictReader((output/'focused.csv').open()))
    expected=Counter()
    for name in ('test-native-arithmetic-parity.R','test-arithmetic-payload-lifetime.R','test-compact-float-domain.R'):
        for title in re.findall(r'^test_that\("([^"\\]*)"', (tests/name).read_text(),re.M):expected[name,title]+=1
    need(Counter((r['file'],r['test']) for r in rows)==expected,'Incomplete focused block matrix')
    for row in rows:
        need(all(re.fullmatch('[0-9]+',row[k]) for k in ('passed','failed','warning')),'Malformed count')
        need(row['error'] in ('TRUE','FALSE') and row['skipped'] in ('TRUE','FALSE'),'Malformed flags')
        need(row['failed']=='0' and row['warning']=='0' and row['error']=='FALSE' and row['skipped']=='FALSE','Failed/skipped focused test')
    totals={k:sum(int(r[k]) for r in rows) for k in ('passed','failed','warning')}
    write(output/'completion.json',dict(status='PASS',blocks=len(rows),totals=totals,before_after_equal=True,
        source_commit=before['build']['receipt']['base_commit'],test_source_head=before['test_source_head'],
        artifacts={p.name:sha(p) for p in output.iterdir() if p.is_file()}))
    print('PASS',len(rows),'blocks;',totals)
if __name__=='__main__':main()

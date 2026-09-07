#!/usr/bin/env python3
"""Probe the real runner's preflight; a synthetic git stops before workloads."""
import argparse, hashlib, json, os, pathlib, shutil, subprocess
p=argparse.ArgumentParser(); p.add_argument('output'); args=p.parse_args()
out=pathlib.Path(args.output).resolve(); out.mkdir()
root=pathlib.Path('/private/tmp/dta-direct-stage4')
runner=root/'benchmarks/r-reference-mutation/owned-atoms.R'
lib='/private/tmp/dta-direct-stage4-validation/candidate-e343b3b-library'
sha='e343b3b56a8529e9ee0ac40f8bd88beebcd2be15'
bin_dir=out/'synthetic-bin'; bin_dir.mkdir()
git=bin_dir/'git'; git.write_text('#!/bin/sh\nprintf called > "$PREFLIGHT_SENTINEL"\nexit 71\n'); git.chmod(0o755)
def state(path):
    return [{'path':str(x.relative_to(path)), 'mode':x.lstat().st_mode,
             'sha256':hashlib.sha256(x.read_bytes()).hexdigest() if x.is_file() else None}
            for x in sorted(path.rglob('*'))] if path.exists() else None
cases=[]
for name in ['empty','unrelated','hidden','nested','empty-child','csv','identity','missing']:
    dest=out/name
    if name!='missing': dest.mkdir()
    if name in ['unrelated','hidden','csv','identity']:
        file={'unrelated':'stale.txt','hidden':'.stale','csv':'owned-native-atoms.csv','identity':'owned-native-atoms-session.txt'}[name]
        (dest/file).write_text('preserve me\n')
    if name in ['nested','empty-child']:
        (dest/'child').mkdir()
        if name=='nested': (dest/'child'/'stale.txt').write_text('preserve me\n')
    sentinel=out/(name+'-sentinel'); before=state(dest)
    env=os.environ.copy(); env['PATH']=str(bin_dir)+os.pathsep+env['PATH']; env['PREFLIGHT_SENTINEL']=str(sentinel)
    command=['Rscript',str(runner),lib,sha,str(dest)]
    run=subprocess.run(command,cwd=root,env=env,capture_output=True)
    (out/(name+'.stdout')).write_bytes(run.stdout); (out/(name+'.stderr')).write_bytes(run.stderr)
    unchanged=state(dest)==before
    passed=run.returncode!=0 and unchanged and (sentinel.exists()==(name=='empty'))
    cases.append(dict(case=name,command=command,exit_code=run.returncode,sentinel=sentinel.exists(),unchanged=unchanged,passed=passed))
record={'kind':'actual R runner preflight with explicitly synthetic git boundary; no measured workloads',
        'source':sha,'runner_sha256':hashlib.sha256(runner.read_bytes()).hexdigest(),'cases':cases}
(out/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(cases,indent=2))
raise SystemExit(0 if all(c['passed'] for c in cases) else 1)

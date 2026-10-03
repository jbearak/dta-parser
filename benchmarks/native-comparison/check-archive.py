#!/usr/bin/env python3
"""Preserve a complete, unchanged R CMD check of the exact retained archive.
This maintained replay entry point adds explicit executable checks to the
original diagnostic snapshot. It is not the controller used for the published
historical check and does not replace its receipt or failed-conformance record.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

def sha(p):
    with Path(p).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def find_r_tools():
    found_r = shutil.which('R')
    found_rs = shutil.which('Rscript')
    if not found_r or not found_rs:
        raise RuntimeError('R and Rscript must both be available on PATH')
    return str(Path(found_r).resolve()), str(Path(found_rs).resolve())


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=Path,required=True)
    p.add_argument('--binding',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();out=args.output.resolve();archive=args.archive.resolve()
    binding=json.loads(args.binding.read_text())
    if sha(archive)!=binding['archive_sha256']:raise RuntimeError('Retained archive changed')
    r, rs = find_r_tools()
    out.mkdir(parents=True,exist_ok=False)
    env=dict(os.environ,R_ENVIRON_USER='/dev/null',R_PROFILE_USER='/dev/null')
    home=Path(subprocess.check_output([r,'--vanilla','--slave','-e','cat(R.home())'],env=env,text=True).strip())
    script_home=Path(subprocess.check_output([rs,'--vanilla','-e','cat(R.home())'],env=env,text=True).strip())
    if sha(home/'bin/exec/R')!=sha(script_home/'bin/exec/R'):raise RuntimeError('R and Rscript runtimes differ')
    command=[r,'CMD','check','--no-manual',str(archive)]
    before=dict(archive_sha256=sha(archive),source_binding_sha256=sha(args.binding),
        R_launcher_sha256=sha(r),Rscript_launcher_sha256=sha(rs),R_runtime_sha256=sha(home/'bin/exec/R'),
        controller_sha256=sha(__file__),started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        command=command,known_environment_overrides={'R_ENVIRON_USER':'/dev/null','R_PROFILE_USER':'/dev/null'},
        limitations='The original Rcheck directory and installation environment were not retained. This reruns the actual check installer on the exact retained source archive, including unchanged examples and tests, and preserves all new artifacts. It does not assert byte-identical reconstruction of the removed library.')
    (out/'install-before.json').write_text(json.dumps(before,indent=2)+'\n')
    with (out/'check.log').open('w') as log:status=subprocess.run(command,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT)
    package=out/'dtatools.Rcheck/dtatools'
    if not (package/'DESCRIPTION').exists():raise RuntimeError('Check installation absent; retained log explains failure')
    installed={str(f.relative_to(package)):sha(f) for f in sorted(package.rglob('*')) if f.is_file()}
    after=dict(archive_sha256=sha(archive),source_binding_sha256=sha(args.binding),
        R_launcher_sha256=sha(r),Rscript_launcher_sha256=sha(rs),R_runtime_sha256=sha(home/'bin/exec/R'),
        controller_sha256=sha(__file__))
    if any(before[k]!=v for k,v in after.items()):raise RuntimeError('Archive/runtime/launcher/controller/binding changed')
    (out/'install-after.json').write_text(json.dumps(after,indent=2)+'\n')
    receipt=dict(kind='diagnostic-full-archive-check',library=str(package.parent),
        installed_inventory=installed,toolchain={'R_runtime_sha256':before['R_runtime_sha256']},
        provenance=before,check_exit_code=status.returncode,check_log_sha256=sha(out/'check.log'),
        finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        original_target_sha256=binding['source_inventory']['tests/testthat/test-metadata-execution-profile.R'],
        test_outputs={str(f.relative_to(out)):sha(f) for f in sorted((out/'dtatools.Rcheck/tests').rglob('*')) if f.is_file()})
    (out/'installation-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'check_exit_code':status.returncode,'library':str(package.parent),'files':len(installed)}))
    raise SystemExit(status.returncode)

if __name__=='__main__':main()

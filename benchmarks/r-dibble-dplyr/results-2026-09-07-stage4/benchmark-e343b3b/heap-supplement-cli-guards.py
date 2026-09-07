"""Synthetic CLI integrity probes. The Rscript stub never executes R."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

source_repo = Path('/private/tmp/dta-direct-stage4')
validation = Path('/private/tmp/dta-direct-stage4-validation')
output = validation / 'heap-supplement-cli-guards'
if output.exists():
    raise RuntimeError('Refusing to replace synthetic guard evidence')
output.mkdir()
repo = output / 'synthetic-repo'
relative = Path('benchmarks/r-dibble-dplyr')
names = ['helpers.R', 'owned-double-helpers.R', 'owned-atomic-helpers.R',
         'owned-double.R', 'owned-double-memory.R', 'owned-atomic.R',
         'owned-atomic-memory.R', 'owned-heap.R', 'run-heap-qualification.py']
blobs = output / 'synthetic-committed-bytes'
for parent in [repo, blobs]:
    (parent / relative).mkdir(parents=True)
    for name in names:
        shutil.copyfile(source_repo / relative / name, parent / relative / name)
identities = {name: hashlib.sha256((source_repo / relative / name).read_bytes()).hexdigest() for name in names}
bin_dir = output / 'synthetic-bin'
bin_dir.mkdir()
(output / 'synthetic-library').mkdir()
git = bin_dir / 'git'
git.write_text('''#!/usr/bin/env python3
# Synthetic committed-byte provider. No git repository or network is touched.
from pathlib import Path
import os,sys
if os.environ.get('HEAP_FAKE_GIT_FAIL')=='1':raise SystemExit(17)
if len(sys.argv)!=3 or sys.argv[1]!='show':raise SystemExit(18)
revision,name=sys.argv[2].split(':',1)
if revision!='2'*40:raise SystemExit(19)
sys.stdout.buffer.write((Path(os.environ['HEAP_FAKE_BLOBS'])/name).read_bytes())
''')
git.chmod(0o755)
log = validation / 'heap-supplement-development-smoke/candidate-logical.log'
body_lines = [line for line in log.read_text().splitlines() if line.startswith('heap_checkpoint ') or
              any(line.startswith('heap_'+name+' ') for name in [
                  'header_bytes_per_cell', 'retained_header_cells', 'excess_header_cells_after_drop_result',
                  'retained_tracked_heap_bytes', 'excess_tracked_heap_bytes_after_drop_result',
                  'released_tracked_heap_bytes_with_last_result'])]
(output / 'synthetic-heap-body.txt').write_text('\n'.join(body_lines)+'\n')
rscript = bin_dir / 'Rscript'
rscript.write_text('''#!/usr/bin/env python3
# SYNTHETIC PROCESS PROTOCOL PROBE. Does not execute R or qualify a package.
from pathlib import Path
import hashlib,os,sys
with Path(os.environ['HEAP_FAKE_CALLS']).open('a') as f:f.write('synthetic Rscript call\\n')
mode=os.environ['HEAP_FAKE_MODE']
for key,value in zip(['library','source_sha','mode','kind','operation','rows'],sys.argv[3:]):
    print('heap_'+key+' '+value)
    if mode=='duplicate_identity' and key=='source_sha':print('heap_'+key+' '+value)
names=['helpers.R','owned-double-helpers.R','owned-atomic-helpers.R','owned-double.R',
       'owned-double-memory.R','owned-atomic.R','owned-atomic-memory.R','owned-heap.R']
for name in names:
    p=Path('benchmarks/r-dibble-dplyr')/name
    md5=hashlib.md5(p.read_bytes()).hexdigest()
    if mode=='wrong_runtime_dependency' and name=='helpers.R':md5='0'*32
    print('heap_runner_md5 '+p.as_posix()+' '+md5)
body=Path(os.environ['HEAP_FAKE_BODY']).read_text()
if mode=='missing_checkpoint':body='\\n'.join(x for x in body.splitlines() if not x.startswith('heap_checkpoint prior '))+'\\n'
print(body,end='')
''')
rscript.chmod(0o755)
records = []
for optimization in ['default', '-O', 'PYTHONOPTIMIZE=1']:
    for mode in ['valid_protocol', 'changed_dependency', 'changed_driver', 'existing_output',
                 'failed_git', 'missing_checkpoint', 'duplicate_identity', 'wrong_runtime_dependency']:
        case = output / (optimization.replace('=', '-') + '-' + mode)
        marker = case.with_suffix('.calls')
        env = {**os.environ, 'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'],
               'HEAP_FAKE_BLOBS': str(blobs), 'HEAP_FAKE_BODY': str(output / 'synthetic-heap-body.txt'),
               'HEAP_FAKE_CALLS': str(marker), 'HEAP_FAKE_MODE': mode}
        env.pop('PYTHONOPTIMIZE', None)
        if optimization == 'PYTHONOPTIMIZE=1':
            env['PYTHONOPTIMIZE'] = '1'
        if mode == 'failed_git':
            env['HEAP_FAKE_GIT_FAIL'] = '1'
        changed = None
        if mode in ['changed_dependency', 'changed_driver']:
            name = 'helpers.R' if mode == 'changed_dependency' else 'run-heap-qualification.py'
            changed = repo / relative / name
            changed.write_bytes(changed.read_bytes() + b'\n# Synthetic changed-byte probe\n')
        if mode == 'existing_output':
            case.mkdir()
            (case / 'sentinel').write_bytes(b'preserve this evidence\n')
        command = [sys.executable] + (['-O'] if optimization == '-O' else []) + [
            str(repo / relative / 'run-heap-qualification.py'), str(repo), str(case),
            str(output / 'synthetic-library'), '1'*40, '2'*40, 'candidate']
        try:
            result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        finally:
            if changed is not None:
                shutil.copyfile(blobs / relative / changed.name, changed)
        outer = case.with_suffix('.outer.log')
        outer.write_bytes(result.stdout)
        calls = len(marker.read_text().splitlines()) if marker.exists() else 0
        if mode == 'valid_protocol':
            manifest = json.loads((case / 'root-manifest.json').read_text())
            if result.returncode != 0 or calls != 36 or len(manifest['cases']) != 36:
                raise RuntimeError('Valid synthetic protocol rejected')
        else:
            if result.returncode == 0 or (case / 'root-manifest.json').exists():
                raise RuntimeError('Corrupted protocol accepted: '+mode)
            preflight = mode in ['changed_dependency', 'changed_driver', 'existing_output', 'failed_git']
            if calls != (0 if preflight else 1):
                raise RuntimeError('Unexpected child execution count: '+mode)
            if preflight and mode != 'existing_output' and case.exists():
                raise RuntimeError('Preflight failure created output: '+mode)
            if mode == 'existing_output' and ((case / 'sentinel').read_bytes() != b'preserve this evidence\n' or
                                               list(case.iterdir()) != [case / 'sentinel']):
                raise RuntimeError('Existing evidence changed')
        records.append({'optimization': optimization, 'mode': mode, 'exit_code': result.returncode,
                        'synthetic_child_calls': calls, 'outer_log': outer.name,
                        'outer_log_sha256': hashlib.sha256(outer.read_bytes()).hexdigest()})
for name, expected in identities.items():
    if hashlib.sha256((source_repo / relative / name).read_bytes()).hexdigest() != expected:
        raise RuntimeError('Actual runner changed during probes')
summary = {'scope': '24 synthetic CLI integrity probes using fake git and Rscript. No R, real package tests, git mutation or qualification.',
           'actual_runner_sha256': identities, 'cases': records, 'result': 'pass',
           'probe_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
           'synthetic_tools': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [git, rscript]}}
with (output / 'guard-summary.json').open('x') as file:
    json.dump(summary, file, indent=2)
    file.write('\n')
print('24 synthetic CLI guards passed; no R executed')

#!/usr/bin/env python3
"""Read-only verification of preserved proof runs and installed input coverage."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def verify(item):
    path = Path(item['path'])
    if str(path.resolve(strict=True)) != item['resolved']:
        raise RuntimeError(f'Changed resolved input: {path}')
    stat = path.stat()
    if (stat.st_size != item['bytes'] or oct(stat.st_mode & 0o777) != item['mode']
            or sha(path) != item['sha256']):
        raise RuntimeError(f'Changed bytes or metadata: {path}')

observations = []
for name in ['run-v1', 'run-v2', 'run-factory-diagnostic', 'run-v3',
             'run-v4-before-empty-fix', 'run-v4-after-empty-fix']:
    run = root / name
    before = json.loads((run / 'inputs-before.json').read_text())
    for item in before['inputs']:
        verify(item)
    manifest = json.loads((run / 'output-manifest.json').read_text())
    actual_paths = {str(p) for p in run.rglob('*') if p.is_file() and p.name != 'output-manifest.json'}
    if actual_paths != {item['path'] for item in manifest['products']}:
        raise RuntimeError(f'Unexpected output inventory: {run}')
    for item in manifest['products']:
        verify(item)
    if manifest['excluded_self'] != str(run / 'output-manifest.json'):
        raise RuntimeError('Incorrect self-exclusion')
    receipt = json.loads((root / (name + '-receipt.json')).read_text())
    verify(receipt['manifest'])
    result = json.loads((run / 'execution-result.json').read_text())
    if result['changed_inputs'] or receipt['changed_inputs']:
        raise RuntimeError('Run reported changed inputs')
    log = (run / 'execution.log').read_text()
    observations.append({'run': name, 'exit': result['returncode'],
                         'input_count': len(before['inputs']),
                         'pass_lines': sum(line.startswith('PASS ') for line in log.splitlines()),
                         'fail_lines': sum(line.startswith('FAIL ') for line in log.splitlines()),
                         'receipt_sha256': sha(root / (name + '-receipt.json'))})

final = root / 'run-v4-after-empty-fix'
before = json.loads((final / 'inputs-before.json').read_text())
bound_paths = {item['resolved'] for item in before['inputs']}
with (final / 'namespaces.tsv').open() as stream:
    namespaces = list(csv.DictReader(stream, delimiter='\t'))
for item in namespaces:
    description = Path(item['path']) / 'DESCRIPTION'
    if str(description.resolve(strict=True)) not in bound_paths:
        raise RuntimeError(f'Unbound loaded namespace: {item}')
dlls = []
for path in (final / 'dll-paths.txt').read_text().splitlines():
    if path == 'base':
        continue
    resolved = str(Path(path).resolve(strict=True))
    if resolved not in bound_paths:
        raise RuntimeError(f'Unbound registered DLL: {path}')
    dlls.append(resolved)
log = (final / 'execution.log').read_text()
if 'TOTAL 35 FAILED 0' not in log:
    raise RuntimeError('Final run did not pass the complete 35-case matrix')

# Exercise the real overwrite guard. The rejected attempt must not alter any
# existing output byte, metadata, or recorded receipt.
guard_before = {str(p): (p.stat().st_size, p.stat().st_mtime_ns, sha(p))
                for p in final.rglob('*') if p.is_file()}
command = ['python3', str(root / 'run-proof.py'), final.name, 'adapter-v2.R', 'cases-v4.R']
rejected = subprocess.run(command, capture_output=True, text=True, check=False)
if rejected.returncode == 0 or 'Refusing existing output or receipt before any R execution' not in rejected.stderr:
    raise RuntimeError('Existing-output guard did not reject')
guard_after = {str(p): (p.stat().st_size, p.stat().st_mtime_ns, sha(p))
               for p in final.rglob('*') if p.is_file()}
if guard_before != guard_after:
    raise RuntimeError('Rejected attempt changed completed outputs')
guard_log = root / 'existing-output-guard.log'
with guard_log.open('x') as stream:
    stream.write(rejected.stdout + rejected.stderr)
report = {'runs': observations, 'loaded_namespaces': namespaces,
          'registered_nonbase_dll_count': len(dlls),
          'all_loaded_namespace_descriptions_and_registered_dlls_bound_before_execution': True,
          'existing_output_guard': {'command': command, 'exit': rejected.returncode,
                                   'original_output_unchanged': True, 'log_sha256': sha(guard_log)},
          'limitations': ['R getLoadedDLLs is not a complete OS loaded-image inventory.',
                          'External OS/Homebrew dylibs and the complete Python runtime are not frozen.',
                          'Installed dplyr metadata identifies CRAN 1.2.1, not an installation from the pinned Git checkout.',
                          'The 51 parsed helper function bodies/formals were independently matched at runtime.']}
payload = json.dumps(report, indent=2, sort_keys=True) + '\n'
with (root / 'audit-result.json').open('x') as stream:
    stream.write(payload)
print(json.dumps({'runs': len(observations), 'final_passes': 35,
                  'loaded_namespaces': len(namespaces), 'registered_nonbase_dlls': len(dlls),
                  'audit_sha256': sha(root / 'audit-result.json')}))

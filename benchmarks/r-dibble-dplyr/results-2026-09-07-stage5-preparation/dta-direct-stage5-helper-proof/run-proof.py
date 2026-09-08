#!/usr/bin/env python3
"""Run a fresh, input-bound standalone helper experiment. No timings."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
UPSTREAM = Path('/private/tmp/dta-direct-stage1-validation/upstream/dplyr')
REVISION = '95740975c465c29cdb2abdfa13effddb948444dc'
RROOT = Path('/opt/homebrew/Cellar/r/4.6.1/lib/R')
SITE = Path('/opt/homebrew/lib/R/4.6/site-library')
PACKAGES = ['dplyr', 'cli', 'generics', 'glue', 'lifecycle', 'magrittr', 'pillar',
            'R6', 'rlang', 'tibble', 'tidyselect', 'vctrs', 'utf8', 'pkgconfig', 'withr']

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def record(path):
    target = path.resolve(strict=True)
    if not target.is_file():
        raise RuntimeError(f'Not a regular input: {path}')
    stat = target.stat()
    return {'path': str(path), 'resolved': str(target), 'bytes': stat.st_size,
            'mode': oct(stat.st_mode & 0o777), 'sha256': digest(target)}

def write_new(path, value):
    content = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(content)

def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
    if len(sys.argv) != 4:
        raise RuntimeError('Usage: run-proof.py OUTPUT_BASENAME ADAPTER_BASENAME CASES_BASENAME')
    output_name, adapter_name, cases_name = sys.argv[1:]
    for name in (output_name, adapter_name, cases_name):
        if Path(name).name != name or name in ('', '.', '..'):
            raise RuntimeError('Only direct-child names are accepted')
    output = ROOT / output_name
    receipt = ROOT / (output_name + '-receipt.json')
    if output.exists() or output.is_symlink() or receipt.exists() or receipt.is_symlink():
        raise RuntimeError('Refusing existing output or receipt before any R execution')
    adapter = ROOT / adapter_name
    cases = ROOT / cases_name
    actual_revision = subprocess.check_output(['git', '-C', str(UPSTREAM), 'rev-parse', 'HEAD'], text=True).strip()
    if actual_revision != REVISION:
        raise RuntimeError('Unexpected pristine source revision')
    git_state = subprocess.check_output(['git', '-C', str(UPSTREAM), 'status', '--porcelain'], text=True)
    if git_state:
        raise RuntimeError('Upstream source tree is not pristine')
    inputs = {Path(__file__).resolve(), adapter, cases}
    upstream_paths = subprocess.check_output(['git', '-C', str(UPSTREAM), 'ls-files', '-z']).split(b'\0')
    inputs.update(UPSTREAM / os.fsdecode(path) for path in upstream_paths if path)
    for package in PACKAGES:
        package_root = SITE / package
        if not package_root.is_dir():
            raise RuntimeError(f'Missing installed dependency {package}')
        inputs.update(path for path in package_root.rglob('*') if path.is_file())
    # Base/recommended libraries and runtime files are bound before execution.
    inputs.update(path for path in RROOT.rglob('*') if path.is_file())
    inputs.add(Path('/opt/homebrew/Cellar/r/4.6.1/bin/Rscript'))
    before = [record(path) for path in sorted(inputs)]
    output.mkdir()
    command = ['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript', '--vanilla', str(cases), str(adapter), str(output)]
    environment = dict(os.environ)
    environment.update(R_LIBS=str(SITE), R_LIBS_SITE=str(SITE),
                       R_LIBS_USER=str(ROOT / 'nonexistent-user-library'))
    manifest = {'created_utc': stamp(), 'command': command, 'source_revision': actual_revision,
                'inputs': before, 'environment_overrides': {key: environment[key] for key in
                ('R_LIBS', 'R_LIBS_SITE', 'R_LIBS_USER')},
                'scope': 'Executable scripts, complete pristine dplyr checkout, installed R tree and 15 package trees. '
                         'Host OS, system/homebrew external dylibs and Python runtime closure are not frozen.'}
    write_new(output / 'inputs-before.json', manifest)
    code = None
    changed = []
    started = stamp()
    try:
        with (output / 'execution.log').open('x') as log:
            code = subprocess.run(command, cwd=ROOT, env=environment, stdout=log,
                                  stderr=subprocess.STDOUT, check=False).returncode
    finally:
        for item in before:
            if record(Path(item['path'])) != item:
                changed.append(item['path'])
        write_new(output / 'execution-result.json', {'started_utc': started, 'finished_utc': stamp(),
                  'returncode': code, 'changed_inputs': changed})
        # Materialize inventory before opening its destination, which is excluded.
        products = [record(path) for path in sorted(output.rglob('*')) if path.is_file()
                    and path.name != 'output-manifest.json']
        write_new(output / 'output-manifest.json', {'products': products,
                  'excluded_self': str(output / 'output-manifest.json')})
        write_new(receipt, {'output': str(output), 'manifest': record(output / 'output-manifest.json'),
                           'returncode': code, 'changed_inputs': changed})
    if changed:
        raise RuntimeError(f'{len(changed)} bound input files changed')
    if code != 0:
        raise RuntimeError(f'R experiment failed with exit {code}; preserved at {output}')
    print(json.dumps({'output': str(output), 'returncode': code, 'inputs': len(before),
                      'receipt_sha256': digest(receipt)}))

if __name__ == '__main__':
    main()

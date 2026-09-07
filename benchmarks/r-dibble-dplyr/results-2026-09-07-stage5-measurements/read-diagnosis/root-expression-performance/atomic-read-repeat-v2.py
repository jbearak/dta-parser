"""Run a bounded atomic-read diagnosis against an exact installation."""
from pathlib import Path
import csv
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
REPO = Path('/private/tmp/dta-direct-stage4')
HELPER = REPO / 'benchmarks/r-dibble-dplyr/helpers.R'
R_ROOT = Path('/opt/homebrew/Cellar/r/4.6.1/lib/R')
RSCRIPT = Path('/opt/homebrew/Cellar/r/4.6.1/bin/Rscript')
SITE = Path('/opt/homebrew/lib/R/4.6/site-library')
RUNNER_SOURCE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'



def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            result.update(block)
    return result.hexdigest()


def identity(path):
    resolved = path.resolve(strict=True)
    st = resolved.stat()
    return {'path': str(path), 'resolved': str(resolved), 'bytes': st.st_size,
            'mode': oct(st.st_mode & 0o777), 'sha256': sha(resolved)}


def write(path, value):
    contents = json.dumps(value, indent=2) + '\n'
    with path.open('x') as stream:
        stream.write(contents)


def input_changes(before):
    changes = []
    for item in before:
        try:
            current = identity(Path(item['path']))
        except (OSError, RuntimeError) as error:
            changes.append({'path': item['path'], 'error': str(error)})
        else:
            if current != item:
                changes.append({'path': item['path'], 'current': current})
    return changes


def main():
    if len(sys.argv) != 6:
        raise RuntimeError('Usage: run.py SOURCE_SHA LIBRARY NEW_OUTPUT_NAME CASE_SET baseline|candidate')
    source, library, name, case_set, mode = sys.argv[1:]
    if case_set not in ('reads_repeat', 'reads_minimum', 'arrow_repeat') or mode not in ('baseline', 'candidate'):
        raise RuntimeError('Invalid bounded read case set or mode')
    script = ROOT / 'atomic-read-repeat-v2.R'
    library = Path(library).resolve(strict=True)
    if not re.fullmatch('[0-9a-f]{40}', source):
        raise RuntimeError('Expected a full source SHA')
    if Path(name).name != name or name in ('', '.', '..'):
        raise RuntimeError('Output must be a fresh direct child')
    output = ROOT / name
    receipt = ROOT / (name + '-receipt.json')
    if any(p.exists() or p.is_symlink() for p in (output, receipt)):
        raise RuntimeError('Refusing existing output or receipt')
    helper_names = ['helpers.R', 'owned-double-helpers.R', 'owned-atomic-helpers.R',
                    'owned-atomic.R', 'owned-atomic-memory.R']
    helper_paths = [REPO / 'benchmarks/r-dibble-dplyr' / name for name in helper_names]
    for path in helper_paths:
        expected = subprocess.check_output(['git', 'show',
            RUNNER_SOURCE + ':' + str(path.relative_to(REPO))], cwd=REPO)
        if path.read_bytes() != expected:
            raise RuntimeError('Helper differs from pinned runner source: ' + str(path))
    inputs = {Path(__file__).resolve(), Path(sys.executable).resolve(), script, RSCRIPT, *helper_paths}
    for directory in [R_ROOT, library / 'dtatools', SITE]:
        if not directory.is_dir():
            raise RuntimeError('Missing input directory: ' + str(directory))
        inputs.update(p for p in directory.rglob('*') if p.is_file())
    before = [identity(p) for p in sorted(inputs)]
    bound_paths = {x['resolved'] for x in before}
    environment = dict(os.environ)
    environment.update(R_LIBS=str(library), R_LIBS_SITE=str(SITE),
        R_LIBS_USER=str(ROOT / 'nonexistent-user-library'),
        R_PROFILE_USER='/dev/null', R_ENVIRON_USER='/dev/null',
        DTA_ATOMIC_REPEAT_CASES=case_set)
    for key in ['R_HOME', 'R_ARCH', 'DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH']:
        environment.pop(key, None)
    command = [str(RSCRIPT), '--vanilla', str(script), str(library), str(output), source, mode, '7']
    output.mkdir()
    write(output / 'inputs-before.json', {'source': source, 'case_set': case_set, 'mode': mode, 'runner_source': RUNNER_SOURCE, 'command': command,
        'inputs': before, 'scope': 'Bounded existing atomic read cases with the original fixtures, checks and seven-iteration measurement loop. The original independent four-row rename warm-up is restored before each measured fixture, outside profiling and timing. The minimum case changes only measured table width to one column. Raw timing series and source states are retained. No full-matrix or cause claim. Timings require an externally coordinated quiet window. '
        'Runtime, declared package trees and exact installation are bound. '
        'External OS/Homebrew dylibs and full Python closure are not frozen.'})
    result = None
    integrity_error = None
    changed = []
    namespace_coverage = False
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        with (output / 'execution.log').open('xb') as log:
            result = subprocess.run(command, cwd=REPO, env=environment,
                stdout=log, stderr=subprocess.STDOUT).returncode
        if result == 0:
            with (output / 'namespaces.tsv').open() as stream:
                for item in csv.DictReader(stream, delimiter='\t'):
                    path = (Path(item['path']) / 'DESCRIPTION').resolve(strict=True)
                    if str(path) not in bound_paths:
                        raise RuntimeError('Unbound namespace: ' + item['name'])
            namespace_coverage = True
    except BaseException as error:
        integrity_error = repr(error)
        raise
    finally:
        changed = input_changes(before)
        write(output / 'execution-result.json', {'returncode': result,
            'changed_inputs': changed, 'namespace_coverage': namespace_coverage, 'integrity_error': integrity_error,
            'started_utc': start,
            'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
        products = [identity(p) for p in sorted(output.iterdir()) if p.is_file()]
        write(output / 'manifest.json', {'products': products, 'excluded_self': 'manifest.json'})
        write(receipt, {'manifest': identity(output / 'manifest.json'),
            'returncode': result, 'changed_inputs': changed,
            'namespace_coverage': namespace_coverage, 'integrity_error': integrity_error,
            'accepted': result == 0 and not changed and namespace_coverage and integrity_error is None})
    if result != 0 or changed or not namespace_coverage:
        raise RuntimeError('Characterization failed; inspect preserved outputs')
    print((output / 'execution.log').read_text())
    print('Receipt SHA256', sha(receipt))


if __name__ == '__main__':
    main()

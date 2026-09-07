"""Run the small public expression characterization against an exact installation."""
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
PACKAGES = ['dplyr', 'cli', 'generics', 'glue', 'lifecycle', 'magrittr', 'pillar',
            'R6', 'rlang', 'tibble', 'tidyselect', 'vctrs', 'utf8', 'pkgconfig', 'withr', 'data.table', 'bench', 'profmem']


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
    if len(sys.argv) != 5:
        raise RuntimeError('Usage: run.py SOURCE_SHA LIBRARY NEW_OUTPUT_NAME CASE_SET')
    source, library, name, case_set = sys.argv[1:]
    if case_set != 'measure':
        raise RuntimeError('Expected measure case set')
    script = ROOT / 'measure.R'
    library = Path(library).resolve(strict=True)
    if not re.fullmatch('[0-9a-f]{40}', source):
        raise RuntimeError('Expected a full source SHA')
    if Path(name).name != name or name in ('', '.', '..'):
        raise RuntimeError('Output must be a fresh direct child')
    output = ROOT / name
    receipt = ROOT / (name + '-receipt.json')
    if any(p.exists() or p.is_symlink() for p in (output, receipt)):
        raise RuntimeError('Refusing existing output or receipt')
    committed = subprocess.check_output(['git', 'show',
        source + ':benchmarks/r-dibble-dplyr/helpers.R'], cwd=REPO)
    if (REPO / 'benchmarks/r-dibble-dplyr/owned-double-helpers.R').read_bytes() != subprocess.check_output(['git', 'show', source + ':benchmarks/r-dibble-dplyr/owned-double-helpers.R'], cwd=REPO):
        raise RuntimeError('Owned helper differs from source commit')
    if HELPER.read_bytes() != committed:
        raise RuntimeError('Helper differs from source commit')
    inputs = {Path(__file__).resolve(), Path(sys.executable).resolve(), script, ROOT / 'cases-v10.R', HELPER, REPO / 'benchmarks/r-dibble-dplyr/owned-double-helpers.R', RSCRIPT}
    for directory in [R_ROOT, library / 'dtatools', *(SITE / p for p in PACKAGES)]:
        if not directory.is_dir():
            raise RuntimeError('Missing input directory: ' + str(directory))
        inputs.update(p for p in directory.rglob('*') if p.is_file())
    before = [identity(p) for p in sorted(inputs)]
    bound_paths = {x['resolved'] for x in before}
    environment = dict(os.environ)
    environment.update(R_LIBS=str(library), R_LIBS_SITE=str(SITE),
        R_LIBS_USER=str(ROOT / 'nonexistent-user-library'),
        DTA_ORACLE_HELPER=str(HELPER), DTA_ORACLE_LIBRARY=str(library),
        DTA_ORACLE_SOURCE=source, DTA_ORACLE_OUTPUT=str(output),
        DTA_EXPRESSION_CASES=str(ROOT / 'cases-v10.R'),
        DTA_OWNED_HELPER=str(REPO / 'benchmarks/r-dibble-dplyr/owned-double-helpers.R'))
    command = [str(RSCRIPT), '--vanilla', str(script)]
    output.mkdir()
    write(output / 'inputs-before.json', {'source': source, 'case_set': case_set, 'command': command,
        'inputs': before, 'scope': 'Expression performance matrix with separate correctness checks. Timings require an externally coordinated quiet window. '
        'Runtime, declared package trees and exact installation are bound. '
        'External OS/Homebrew dylibs and full Python closure are not frozen.'})
    result = None
    integrity_error = None
    changed = []
    namespace_coverage = False
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        with (output / 'execution.log').open('xb') as log:
            result = subprocess.run(command, cwd=ROOT, env=environment,
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

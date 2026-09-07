#!/usr/bin/env python3
"""Run the frozen 35 cases on the qualified clean R4.6.0, with no installation."""
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
STUDY = Path('/private/tmp/dta-direct-stage5-minimum-preflight')
ORIGINAL = Path('/private/tmp/dta-direct-stage5-helper-proof')
UPSTREAM = Path('/private/tmp/dta-direct-stage1-validation/upstream/dplyr')
INSTALL = STUDY / 'r460-clean-install'
DEPS = STUDY / 'r460-clean-dependencies'
DPLYR = STUDY / 'r460-clean-dplyr-libraries/1.2.1'
PINNED = {
    ORIGINAL / 'adapter-v2.R': 'c17300a7ff1f30a2389c8ac033c2982ef14f8dd0601c460783bd372182445d0d',
    ORIGINAL / 'cases-v4.R': '3f4540ad6e931127d652382790017fbc11e07265992982542a609a487d1e2ce9',
    ORIGINAL / 'artifact-index.json': 'bb907a08b4566579b6fad1ebad6f2bf8a588e2219ac162c06d2ef43306af1931',
    STUDY / 'manifests/artifact-index.json': 'f1b76e34ba9e53cf0e4dffb3413c213f87bb02fc342b13ee487a0287c8ec9d85',
    STUDY / 'manifests/final-installed-files.json': 'b165221eee1f2565817198f94e391304eae7b291f6c6359b9ffc6738d411e429',
    STUDY / 'runtime-clean-probe/images.so': '23e3f098c2725266e75bd45e6410d462fa267ab16fd6227b23d85782513a3155'
}

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def record(path):
    target = path.resolve(strict=True)
    if not target.is_file():
        raise RuntimeError(f'Not a regular file: {path}')
    stat = target.stat()
    return {'path': str(path), 'resolved': str(target), 'bytes': stat.st_size,
            'mode': oct(stat.st_mode & 0o777), 'sha256': sha(target)}

def write(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(payload)

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
    if len(sys.argv) != 2 or Path(sys.argv[1]).name != sys.argv[1] or sys.argv[1] in ('', '.', '..'):
        raise RuntimeError('Expected one fresh direct-child output name')
    output = ROOT / sys.argv[1]
    receipt = ROOT / (sys.argv[1] + '-receipt.json')
    if any(path.exists() or path.is_symlink() for path in (output, receipt)):
        raise RuntimeError('Existing output or receipt; no R execution')
    for path, expected in PINNED.items():
        if sha(path) != expected:
            raise RuntimeError(f'Changed authoritative input: {path}')
    historical = json.loads((STUDY / 'manifests/final-installed-files.json').read_text())
    for relative, expected in historical.items():
        if sha(STUDY / relative) != expected:
            raise RuntimeError(f'Qualified runtime/dependency changed: {relative}')
    original_index = json.loads((ORIGINAL / 'artifact-index.json').read_text())
    original_paths = {ORIGINAL / item['path'] for item in original_index['files']}
    original_paths |= {ORIGINAL / 'artifact-index.json', ORIGINAL / 'artifact-index-receipt.json'}
    actual_original_paths = {path for path in ORIGINAL.rglob('*') if path.is_file()}
    if original_paths != actual_original_paths:
        raise RuntimeError('Original proof inventory changed')
    for item in original_index['files']:
        actual = record(ORIGINAL / item['path'])
        if any(actual[key] != item[key] for key in ('bytes', 'mode', 'sha256')):
            raise RuntimeError(f'Original proof file changed: {item["path"]}')
    study_index = {item['path']: item for item in json.loads((STUDY / 'manifests/artifact-index.json').read_text())['artifacts']}
    references = ['dplyr-r46-minimum.md', 'manifests/clean-runtime-build.json',
                  'manifests/clean-dependency-installs.json', 'manifests/r460-clean-dplyr-installs.json',
                  'manifests/final-qualification.json', 'manifests/final-installed-files.json',
                  'manifests/dplyr-clean-git-archives.json', 'manifests/dependency-downloads.json',
                  'runtime-clean-probe/check.R', 'runtime-clean-probe/images.c', 'runtime-clean-probe/images.o',
                  'runtime-clean-probe/images.so', 'logs/r460-clean-loaded-library-before.log',
                  'logs/r460-clean-loaded-library-after.log', 'logs/r460-clean-image-probe-build.log']
    inputs = set(PINNED) | original_paths | {Path(__file__).resolve(), ROOT / 'guarded-cases.R'}
    for relative in references:
        path = STUDY / relative
        item = study_index[relative]
        if path.stat().st_size != item['bytes'] or sha(path) != item['sha256']:
            raise RuntimeError(f'Historical provenance changed: {relative}')
        inputs.add(path)
    runtime_paths = set()
    for directory in (INSTALL, DEPS, DPLYR):
        if not directory.is_dir():
            raise RuntimeError(f'Missing qualified installation: {directory}')
        runtime_paths.update(path for path in directory.rglob('*') if path.is_file())
    if runtime_paths != {STUDY / path for path in historical}:
        raise RuntimeError('Qualified runtime/dependency inventory changed')
    inputs |= runtime_paths
    # Bind the eight existing external Homebrew dylibs recorded by the accepted
    # image guard. OS shared-cache image paths are retained as identities only.
    external_dylibs = set()
    for match in re.findall(r'"(/opt/homebrew/[^"\n]+)"', (STUDY / 'logs/r460-clean-loaded-library-after.log').read_text()):
        path = Path(match)
        if not path.is_file():
            raise RuntimeError(f'Previously loaded external library is missing: {path}')
        external_dylibs.add(path)
    inputs |= external_dylibs
    revision = subprocess.check_output(['git', '-C', str(UPSTREAM), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != '95740975c465c29cdb2abdfa13effddb948444dc':
        raise RuntimeError('Unexpected dplyr source revision')
    if subprocess.check_output(['git', '-C', str(UPSTREAM), 'status', '--porcelain'], text=True):
        raise RuntimeError('Pristine dplyr checkout changed')
    tracked = subprocess.check_output(['git', '-C', str(UPSTREAM), 'ls-files', '-z']).split(b'\0')
    inputs |= {UPSTREAM / os.fsdecode(path) for path in tracked if path}
    before = [record(path) for path in sorted(inputs)]
    bound_resolved = {item['resolved'] for item in before}
    overrides = {'R_LIBS': str(DPLYR) + os.pathsep + str(DEPS), 'R_LIBS_SITE': str(DEPS),
                 'R_LIBS_USER': str(ROOT / 'nonexistent-user-library'),
                 'R_ENVIRON_USER': '/dev/null', 'R_PROFILE_USER': '/dev/null', 'R_MAKEVARS_USER': '/dev/null'}
    environment = dict(os.environ)
    cleared = ['DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES',
               'DYLD_FRAMEWORK_PATH', 'DYLD_FALLBACK_FRAMEWORK_PATH', 'R_HOME', 'R_ARCH']
    for name in cleared:
        environment.pop(name, None)
    environment.update(overrides)
    command = [str(INSTALL / 'bin/Rscript'), '--vanilla', str(ROOT / 'guarded-cases.R'),
               str(ORIGINAL / 'adapter-v2.R'), str(output)]
    output.mkdir()
    write(output / 'inputs-before.json', {'created_utc': now(), 'command': command,
          'inputs': before, 'environment_overrides': overrides, 'cleared_environment_keys': cleared,
          'source_revision': revision, 'original_proof_file_count': len(original_paths),
          'historical_installed_file_count': len(historical), 'external_homebrew_dylib_count': len(external_dylibs),
          'scope': 'Unchanged frozen cases/adapter, full qualified R/dependency installation and existing image probe. '
                   'OS shared-cache binaries and complete Python runtime closure are not frozen.'})
    started = now()
    code = None
    changed = []
    coverage = None
    try:
        with (output / 'execution.log').open('x') as log:
            code = subprocess.run(command, env=environment, cwd=ROOT, stdout=log,
                                  stderr=subprocess.STDOUT, check=False).returncode
        if code == 0:
            # Qualify actual loaded namespace/DLL/image paths against the frozen
            # inputs, after both same-process guards and all unchanged cases ran.
            with (output / 'namespaces.tsv').open() as stream:
                namespaces = list(csv.DictReader(stream, delimiter='\t'))
            for item in namespaces:
                if str((Path(item['path']) / 'DESCRIPTION').resolve(strict=True)) not in bound_resolved:
                    raise RuntimeError(f'Unbound loaded namespace: {item}')
            for path in (output / 'dll-paths.txt').read_text().splitlines():
                if path != 'base' and str(Path(path).resolve(strict=True)) not in bound_resolved:
                    raise RuntimeError(f'Unbound registered DLL: {path}')
            images = {}
            for phase in ('before', 'after'):
                paths = (output / f'loaded-images-{phase}.txt').read_text().splitlines()
                for path in paths:
                    if path.startswith(('/opt/homebrew/', str(STUDY) + '/')):
                        if str(Path(path).resolve(strict=True)) not in bound_resolved:
                            raise RuntimeError(f'Unbound non-OS loaded image: {path}')
                images[phase] = {'count': len(paths), 'libR': [path for path in paths if path.endswith('/libR.dylib')]}
            log = (output / 'execution.log').read_text()
            if 'TOTAL 35 FAILED 0' not in log:
                raise RuntimeError('The unchanged 35-case matrix did not pass')
            coverage = {'namespace_count': len(namespaces), 'images': images,
                        'all_non_os_loaded_images_bound': True, 'all_registered_dlls_bound': True}
    finally:
        for item in before:
            if record(Path(item['path'])) != item:
                changed.append(item['path'])
        write(output / 'execution-result.json', {'started_utc': started, 'finished_utc': now(),
              'returncode': code, 'changed_inputs': changed, 'runtime_coverage': coverage})
        products = [record(path) for path in sorted(output.rglob('*')) if path.is_file()
                    and path.name != 'output-manifest.json']
        write(output / 'output-manifest.json', {'products': products,
              'excluded_self': str(output / 'output-manifest.json')})
        write(receipt, {'output_manifest': record(output / 'output-manifest.json'),
                       'returncode': code, 'changed_inputs': changed, 'runtime_coverage': coverage})
    if code != 0 or changed or coverage is None:
        raise RuntimeError(f'Proof failed; preserved at {output}')
    print(json.dumps({'output': str(output), 'returncode': code, 'input_files': len(before),
                      'receipt_sha256': sha(receipt), 'coverage': coverage}))

if __name__ == '__main__':
    main()

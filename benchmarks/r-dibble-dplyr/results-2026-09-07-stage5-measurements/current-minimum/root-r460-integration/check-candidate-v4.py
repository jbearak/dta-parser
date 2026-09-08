"""Run exact-installed checks with only clean minimum-R libraries visible."""
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
STUDY = Path('/private/tmp/dta-direct-stage5-minimum-preflight')
R_INSTALL = STUDY / 'r460-clean-install'
DEPS = [ROOT / 'dependency-build/library', STUDY / 'r460-clean-dplyr-libraries/1.2.1',
        STUDY / 'r460-clean-dependencies']

def identity(path):
    target = path.resolve(strict=True)
    stat = target.stat()
    h = hashlib.sha256()
    with target.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            h.update(block)
    return dict(path=str(path), resolved=str(target), bytes=stat.st_size,
                mode=oct(stat.st_mode & 0o777), sha256=h.hexdigest())

def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')

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


def export_changes(source_root, inventory):
    expected = {item['path']: item for item in inventory}
    current_paths = {str(path) for path in source_root.rglob('*')
                     if path.is_file() or path.is_symlink()}
    changes = [{'path': path, 'error': 'Unexpected export path'}
               for path in sorted(current_paths - set(expected))]
    for path, item in expected.items():
        try:
            current = identity(Path(path))
        except (OSError, RuntimeError) as error:
            changes.append({'path': path, 'error': str(error)})
        else:
            stored = {key: item[key] for key in current}
            if current != stored:
                changes.append({'path': path, 'current': current})
    return changes


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
    if len(sys.argv) != 6:
        raise RuntimeError('Expected SOURCE_SHA INSTALL_NAME OUTPUT_NAME behavior|observe|tests FILTER')
    source, install_name, output_name, mode, test_filter = sys.argv[1:]
    if not re.fullmatch('[0-9a-f]{40}', source):
        raise RuntimeError('Expected full source SHA')
    for name in (install_name, output_name):
        if Path(name).name != name or name in ('', '.', '..'):
            raise RuntimeError('Names must identify direct children')
    if mode not in ('behavior', 'observe', 'tests'):
        raise RuntimeError('Unknown check mode')
    output = ROOT / output_name
    receipt = ROOT / (output_name + '-receipt.json')
    if any(path.exists() or path.is_symlink() for path in (output, receipt)):
        raise RuntimeError('Refusing existing output or receipt')
    installation = ROOT / install_name
    installed_receipt_path = installation / 'completed-receipt.json'
    installed_receipt = json.loads(installed_receipt_path.read_text())
    if installed_receipt['revision'] != source or installed_receipt['status'] != 'complete' or installed_receipt['changed_bound_inputs']:
        raise RuntimeError('Wrong or incomplete source installation')
    manifest = Path(installed_receipt['manifest']['path'])
    if identity(manifest) != installed_receipt['manifest']:
        raise RuntimeError('Installed source manifest changed')
    products = {item['path']: item for item in json.loads(manifest.read_text())['products']}
    for name in ('installed-files.json', 'inputs-before.json'):
        metadata = installation / name
        expected = products.get(str(metadata))
        if expected is None or identity(metadata) != expected:
            raise RuntimeError('Installation inventory metadata is not bound by completed manifest: ' + name)
    for item in json.loads((installation / 'installed-files.json').read_text())['files']:
        if identity(Path(item['path'])) != item:
            raise RuntimeError('Installed package changed')
    original_inputs = json.loads((installation / 'inputs-before.json').read_text())
    for item in original_inputs['export_inventory']:
        content = Path(item['path']).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        if blob != item['git_blob']:
            raise RuntimeError('Exported source changed')
    library = installation / 'library'
    source_root = installation / 'export'
    if export_changes(source_root, original_inputs['export_inventory']):
        raise RuntimeError('Exported source inventory or file identity changed')
    helper = source_root / 'benchmarks/r-dibble-dplyr/helpers.R'
    cases = ROOT / (mode + '-minimum.R') if mode != 'tests' else ROOT / 'check-candidate.R'
    inputs = {Path(__file__).resolve(), Path(sys.executable).resolve(), ROOT / 'check-candidate.R', ROOT / 'runtime-guard.R', cases,
              installed_receipt_path, manifest, installation / 'installed-files.json',
              installation / 'inputs-before.json', STUDY / 'runtime-clean-probe/images.so',
              Path('/opt/homebrew/Cellar/libomp/22.1.8/lib/libomp.dylib')}
    for directory in [R_INSTALL, *DEPS, library, source_root, Path('/opt/homebrew/Cellar/icu4c@78/78.3')]:
        inputs.update(path for path in directory.rglob('*') if path.is_file())
    prior_images = STUDY / 'logs/r460-clean-loaded-library-after.log'
    inputs.add(prior_images)
    for match in re.findall(r'"(/opt/homebrew/[^"\n]+)"', prior_images.read_text()):
        inputs.add(Path(match))
    before = [identity(path) for path in sorted(inputs)]
    bound = {item['resolved'] for item in before}
    libraries = [library, *DEPS, R_INSTALL / 'lib/R/library']
    overrides = dict(R_LIBS=os.pathsep.join(map(str, [library, *DEPS])),
        R_LIBS_SITE=os.pathsep.join(map(str, DEPS)),
        R_LIBS_USER=str(output / 'nonexistent-user-library'),
        R_MAKEVARS_USER='/dev/null', R_PROFILE_USER='/dev/null', R_ENVIRON_USER='/dev/null',
        DTA_ORACLE_HELPER=str(helper), DTA_ORACLE_LIBRARY=str(library), DTA_ORACLE_SOURCE=source,
        DTA_ORACLE_OUTPUT=str(output), DTA_MINIMUM_GUARD=str(ROOT / 'runtime-guard.R'),
        DTA_MINIMUM_LIBRARIES=os.pathsep.join(map(str, libraries)), DTA_MINIMUM_CASES=str(cases),
        DTA_MINIMUM_CHECK=mode, DTA_MINIMUM_TEST_FILTER=test_filter,
        DTA_MINIMUM_SOURCE_ROOT=str(source_root))
    environment = dict(os.environ)
    cleared = ['R_HOME', 'R_ARCH', 'R_DEFAULT_PACKAGES', 'DYLD_INSERT_LIBRARIES',
               'DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH',
               'DYLD_FALLBACK_FRAMEWORK_PATH']
    for key in cleared:
        environment.pop(key, None)
    environment.update(overrides)
    command = [str(R_INSTALL / 'bin/Rscript'), '--vanilla', str(ROOT / 'check-candidate.R')]
    output.mkdir()
    write(output / 'inputs-before.json', dict(inputs=before, source=source, mode=mode,
        command=command, environment_overrides=overrides, cleared_environment_keys=cleared,
        utc=now(), scope='Exact installation/export, full clean R and selected dependency libraries, '
        'native image probe and previously observed Homebrew dylibs plus ICU. OS shared-cache '
        'binaries and full Python closure are not frozen. Image checks observe this R process.'))
    code = None
    integrity_error = None
    coverage = None
    changed = []
    started = now()
    try:
        with (output / 'execution.log').open('x') as log:
            code = subprocess.run(command, cwd=ROOT, env=environment,
                stdout=log, stderr=subprocess.STDOUT).returncode
        coverage = {}
        for phase in ('before', 'after'):
            with (output / ('guard-namespaces-' + phase + '.tsv')).open() as stream:
                namespaces = list(csv.DictReader(stream, delimiter='\t'))
            for item in namespaces:
                if str((Path(item['path']) / 'DESCRIPTION').resolve(strict=True)) not in bound:
                    raise RuntimeError('Unbound namespace ' + item['name'])
            images = (output / ('loaded-images-' + phase + '.txt')).read_text().splitlines()
            for path in images:
                if path.startswith(('/opt/homebrew/', '/private/')) and str(Path(path).resolve(strict=True)) not in bound:
                    raise RuntimeError('Unbound non-OS image ' + path)
            for path in (output / ('guard-dlls-' + phase + '.txt')).read_text().splitlines():
                if path != 'base' and str(Path(path).resolve(strict=True)) not in bound:
                    raise RuntimeError('Unbound registered DLL ' + path)
            coverage[phase] = dict(namespaces=len(namespaces), images=len(images),
                                  libR=[path for path in images if path.endswith('/libR.dylib')])
    except Exception as error:
        integrity_error = str(error)
        raise
    finally:
        changed = input_changes(before)
        changed.extend(export_changes(source_root, original_inputs['export_inventory']))
        write(output / 'execution-result.json', dict(returncode=code, started_utc=started,
            completed_utc=now(), changed_inputs=changed, runtime_coverage=coverage, integrity_error=integrity_error))
        products = [identity(path) for path in sorted(output.rglob('*')) if path.is_file()]
        output_manifest = output / 'output-manifest.json'
        write(output_manifest, dict(products=products, excluded_self=str(output_manifest)))
        write(receipt, dict(manifest=identity(output_manifest), returncode=code,
                           changed_inputs=changed, runtime_coverage=coverage, integrity_error=integrity_error,
                           accepted=code == 0 and not changed and integrity_error is None and set(coverage or {}) == {"before", "after"}))
    if code != 0 or changed or coverage is None:
        raise RuntimeError('Minimum check failed; inspect preserved outputs')
    print(json.dumps(dict(receipt=identity(receipt), runtime_coverage=coverage)))

if __name__ == '__main__':
    main()

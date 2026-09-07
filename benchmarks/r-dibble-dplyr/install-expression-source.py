#!/usr/bin/env python3
"""Build one exact Stage 5 source revision into a fresh, retained library."""
import argparse
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repo', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('revision')
args = parser.parse_args()
GIT_ROOT = args.repo.resolve()
if args.output.exists() or args.output.is_symlink():
    raise RuntimeError('Fresh output required before any work')
ROOT = args.output.resolve()
REVISION = args.revision
TREE = subprocess.check_output(['git', '-C', str(GIT_ROOT), 'rev-parse',
    REVISION + ':r-package/dtatools'], text=True).strip()
R_INSTALL = Path('/opt/homebrew/Cellar/r/4.6.1')
R_HOME_PATH = R_INSTALL / 'lib/R'
SITE = Path('/opt/homebrew/lib/R/4.6/site-library')
EXPORTED = ['r-package/dtatools', 'benchmarks/r-dibble-dplyr/helpers.R',
            'benchmarks/r-dibble-dplyr/expression-install-finish.R',
            'benchmarks/r-dibble-dplyr/install-expression-source.py']

def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def record(path):
    target = path.resolve(strict=True)
    if not target.is_file():
        raise RuntimeError(f'Expected regular input: {path}')
    stat = target.stat()
    return {'path': str(path), 'resolved': str(target), 'bytes': stat.st_size,
            'mode': oct(stat.st_mode & 0o777), 'sha256': sha(target)}

def write(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(payload)

def input_changes(before):
    changes = []
    for item in before:
        try:
            current = record(Path(item['path']))
        except (OSError, RuntimeError) as error:
            changes.append({'path': item['path'], 'error': str(error)})
        else:
            if current != item:
                changes.append({'path': item['path'], 'current': current})
    return changes

def git(*arguments):
    return subprocess.check_output(['/opt/homebrew/bin/git', '-C', str(GIT_ROOT), *arguments])

def dcf(path):
    fields = {}
    current = None
    for line in path.read_text().splitlines():
        if line[:1].isspace() and current:
            fields[current] += ' ' + line.strip()
        elif ':' in line:
            current, value = line.split(':', 1)
            fields[current] = value.strip()
    return fields

def main():
    if ROOT.exists() or ROOT.is_symlink():
        raise RuntimeError('Fresh output required before any work')
    ROOT.mkdir(parents=True)
    reserved = ['source.tar', 'export', 'build', 'library', 'runtime-temp', 'inputs-before.json',
                'execution-result.json', 'output-manifest.json', 'completed-receipt.json']
    if any((ROOT / name).exists() or (ROOT / name).is_symlink() for name in reserved):
        raise RuntimeError('Fresh candidate output required before source export or build')
    actual_revision = git('rev-parse', '--verify', REVISION + '^{commit}').decode().strip()
    actual_tree = git('rev-parse', REVISION + ':r-package/dtatools').decode().strip()
    if actual_revision != REVISION or actual_tree != TREE:
        raise RuntimeError('Unexpected candidate or package identity')
    runner_relative = 'benchmarks/r-dibble-dplyr/install-expression-source.py'
    if Path(__file__).read_bytes() != git('show', REVISION + ':' + runner_relative):
        raise RuntimeError('Installer is not the exact committed candidate runner')
    archive_command = ['/opt/homebrew/bin/git', '-C', str(GIT_ROOT), 'archive', '--format=tar',
                       '--output=' + str(ROOT / 'source.tar'), REVISION, *EXPORTED]
    subprocess.run(archive_command, check=True)
    export = ROOT / 'export'
    export.mkdir()
    with tarfile.open(ROOT / 'source.tar', 'r:') as archive:
        for item in archive.getmembers():
            if Path(item.name).is_absolute() or '..' in Path(item.name).parts or not (item.isdir() or item.isfile()):
                raise RuntimeError(f'Unsafe source archive member: {item.name}')
        archive.extractall(export, filter='data')
    entries = git('ls-tree', '-r', '-z', REVISION, '--', *EXPORTED).split(b'\0')
    export_rows = []
    for entry in entries:
        if not entry:
            continue
        meta, raw_path = entry.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        relative = os.fsdecode(raw_path)
        path = export / relative
        content = path.read_bytes()
        actual_blob = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        if kind != 'blob' or actual_blob != blob:
            raise RuntimeError(f'Exported source does not match Git: {relative}')
        if (path.stat().st_mode & 0o111 != 0) != (mode == '100755'):
            raise RuntimeError(f'Exported executable mode mismatch: {relative}')
        export_rows.append({'path': relative, 'git_blob': blob, 'git_mode': mode, **record(path)})
    actual_paths = {str(path.relative_to(export)) for path in export.rglob('*') if path.is_file()}
    expected_paths = {os.fsdecode(entry.split(b'\t', 1)[1]) for entry in entries if entry}
    if actual_paths != expected_paths:
        raise RuntimeError('Export inventory does not match exact Git tree')
    package_source = export / 'r-package/dtatools'
    dependency_rows = []
    seen = set()
    pending = [dcf(package_source / 'DESCRIPTION')]
    package_dirs = []
    while pending:
        fields = pending.pop()
        for field in ('Depends', 'Imports', 'LinkingTo'):
            for name in re.sub(r'\([^)]*\)', '', fields.get(field, '')).split(','):
                name = name.strip()
                if not name or name == 'R' or name in seen:
                    continue
                seen.add(name)
                candidates = [SITE / name, R_HOME_PATH / 'library' / name]
                directory = next((path for path in candidates if (path / 'DESCRIPTION').is_file()), None)
                if directory is None:
                    raise RuntimeError(f'Missing required dependency {name}; no installation attempted')
                description = dcf(directory / 'DESCRIPTION')
                dependency_rows.append({'package': name, 'version': description.get('Version'), 'path': str(directory)})
                package_dirs.append(directory)
                pending.append(description)
    tool_names = ['git', 'cargo', 'rustc', 'clang', 'cc', 'make', 'tar', 'sh', 'sed', 'uname', 'ar', 'ranlib', 'ld', 'xcrun']
    tools = {name: Path(shutil.which(name)).resolve(strict=True) for name in tool_names}
    compiler = Path(subprocess.check_output(['/usr/bin/xcrun', '--find', 'clang'], text=True).strip())
    sdk = Path(subprocess.check_output(['/usr/bin/xcrun', '--show-sdk-path'], text=True).strip()).resolve(strict=True)
    inputs = {Path(__file__).resolve(), export / 'benchmarks/r-dibble-dplyr/expression-install-finish.R', ROOT / 'source.tar', compiler}
    inputs.update(tools.values())
    inputs.update(path for path in export.rglob('*') if path.is_file())
    # Retain complete installed R, Rust, and selected R dependency file identities.
    rust_install = tools['rustc'].parent.parent
    for directory in [R_INSTALL, rust_install, *package_dirs]:
        inputs.update(path for path in directory.rglob('*') if path.is_file())
    config_candidates = [Path('/Users/jmb/.R/Makevars'), Path('/Users/jmb/.cargo/config'),
                         Path('/Users/jmb/.cargo/config.toml'), sdk / 'SDKSettings.json', sdk / 'SDKSettings.plist']
    for path in config_candidates:
        if path.is_file():
            inputs.add(path)
    absent_configs = [str(path) for path in config_candidates if not path.exists()]
    for name in ['build', 'library', 'runtime-temp']:
        (ROOT / name).mkdir()
    before = [record(path) for path in sorted(inputs)]
    environment = dict(os.environ)
    overrides = {'R_LIBS': str(SITE), 'R_LIBS_SITE': str(SITE),
                 'R_LIBS_USER': str(ROOT / 'nonexistent-user-library'),
                 'R_MAKEVARS_USER': '/Users/jmb/.R/Makevars',
                 'R_ENVIRON_USER': '/dev/null', 'R_PROFILE_USER': '/dev/null',
                 'TMPDIR': str(ROOT / 'runtime-temp'), 'CARGO_NET_OFFLINE': 'true'}
    for name in ['R_HOME', 'R_ARCH', 'RUSTFLAGS', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER',
                 'DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH']:
        environment.pop(name, None)
    environment.update(overrides)
    write(ROOT / 'inputs-before.json', {'created_utc': stamp(), 'revision': REVISION,
          'package_tree': TREE, 'archive_command': archive_command,
          'source_archive': record(ROOT / 'source.tar'), 'export_inventory': export_rows,
          'dependencies': sorted(dependency_rows, key=lambda item: item['package']),
          'tools': {name: str(path) for name, path in tools.items()}, 'sdk_path': str(sdk),
          'inputs': before, 'environment_overrides': overrides, 'absent_configuration_paths': absent_configs,
          'scope': 'Exact Git export and committed installer/helpers; installed R/Rust and required R dependency trees. '
                   'Full SDK/system dynamic-library and Python runtime closures are not frozen.'})
    commands = []
    consumed = []
    def guard():
        changes = input_changes(before + consumed)
        if changes:
            raise RuntimeError('Bound inputs changed: ' + repr(changes))
        current = {str(path.relative_to(export)) for path in export.rglob('*')
                   if path.is_file() or path.is_symlink()}
        if current != expected_paths:
            raise RuntimeError('Export inventory changed: ' + repr(sorted(current.symmetric_difference(expected_paths))))
    def run(label, command, cwd):
        guard()
        log = ROOT / (label + '.log')
        item = {'label': label, 'command': command, 'cwd': str(cwd), 'started_utc': stamp()}
        with log.open('x') as stream:
            item['returncode'] = subprocess.run(command, cwd=cwd, env=environment, stdout=stream,
                                                stderr=subprocess.STDOUT, check=False).returncode
        item['finished_utc'] = stamp()
        item['log'] = record(log)
        commands.append(item)
        write(ROOT / (label + '-command.json'), item)
        guard()
        if item['returncode'] != 0:
            raise RuntimeError(f'{label} failed; retained at {log}')
    status = 'failed'
    changed = []
    try:
        run('r-version', [str(R_INSTALL / 'bin/R'), '--version'], ROOT)
        run('rustc-version', [str(tools['rustc']), '-vV'], ROOT)
        run('cargo-version', [str(tools['cargo']), '-vV'], ROOT)
        run('clang-version', [str(compiler), '--version'], ROOT)
        run('build', [str(R_INSTALL / 'bin/R'), 'CMD', 'build', str(package_source)], ROOT / 'build')
        version = dcf(package_source / 'DESCRIPTION')['Version']
        tarball = ROOT / 'build' / ('dtatools_' + version + '.tar.gz')
        if not tarball.is_file():
            raise RuntimeError('R CMD build did not produce expected source archive')
        consumed.append(record(tarball))
        write(ROOT / 'built-source-before-install.json', consumed[-1])
        run('install', [str(R_INSTALL / 'bin/R'), 'CMD', 'INSTALL',
                         '--library=' + str(ROOT / 'library'), str(tarball)], ROOT / 'build')
        run('finish-install', [str(R_INSTALL / 'bin/Rscript'), '--vanilla', str(export / 'benchmarks/r-dibble-dplyr/expression-install-finish.R'),
             str(ROOT / 'library'), REVISION, TREE, str(tarball),
             str(export / 'benchmarks/r-dibble-dplyr/helpers.R')], ROOT)
        library_inputs = {str(Path(item['resolved'])) for item in before}
        with (ROOT / 'loaded-namespaces.tsv').open() as stream:
            for item in csv.DictReader(stream, delimiter='\t'):
                if item['name'] != 'dtatools' and str((Path(item['path']) / 'DESCRIPTION').resolve(strict=True)) not in library_inputs:
                    raise RuntimeError(f'Unbound loaded dependency: {item}')
        status = 'complete'
    finally:
        changed = input_changes(before + consumed)
        generated = [str(path.relative_to(export)) for path in export.rglob('*')
                     if path.is_file() and str(path.relative_to(export)) not in expected_paths]
        if changed or generated:
            status = 'failed'
        write(ROOT / 'execution-result.json', {'status': status, 'commands': commands,
              'changed_bound_inputs': changed, 'generated_export_files': generated})
        installed = ROOT / 'library/dtatools'
        write(ROOT / 'installed-files.json', {'files': [record(path) for path in sorted(installed.rglob('*')) if path.is_file()]})
        # Snapshot inventory before opening the manifest, excluding its own path
        # and the separate receipt. Temporary build output is retained as observed.
        products = [record(path) for path in sorted(ROOT.rglob('*')) if path.is_file()
                    and path.name not in ('output-manifest.json', 'completed-receipt.json')]
        write(ROOT / 'output-manifest.json', {'products': products,
              'excluded_self': str(ROOT / 'output-manifest.json'), 'excluded_receipt': str(ROOT / 'completed-receipt.json')})
        write(ROOT / 'completed-receipt.json', {'status': status, 'revision': REVISION, 'package_tree': TREE,
              'manifest': record(ROOT / 'output-manifest.json'), 'changed_bound_inputs': changed})
    if status != 'complete' or changed:
        raise RuntimeError('Candidate incomplete or a bound input changed; inspect retained records')
    print(json.dumps({'status': status, 'source': REVISION, 'library': str(ROOT / 'library'),
                      'bound_inputs': len(before), 'exported_files': len(export_rows),
                      'receipt_sha256': sha(ROOT / 'completed-receipt.json')}))

if __name__ == '__main__':
    main()

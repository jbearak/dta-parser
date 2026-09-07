"""Run exact-source Stage 5 checks with before/after input bindings.

Source exports, installed dependencies, original logs and failed attempts stay
in the fresh output directory. Output indexes exclude themselves; a separate
receipt binds the completed index. Integrity checks remain enabled under -O.
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            h.update(block)
    return h.hexdigest()


def identity(path):
    target = path.resolve(strict=True)
    st = target.stat()
    return dict(path=str(path), resolved=str(target), bytes=st.st_size,
                mode=oct(st.st_mode & 0o777), sha256=digest(target))


def write(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(payload)


def require_fresh(path):
    require(not path.exists() and not path.is_symlink(), 'Fresh output required before any work')


def input_changes(before):
    changes = []
    for row in before:
        try:
            current = identity(Path(row['path']))
        except (OSError, RuntimeError) as error:
            changes.append(dict(path=row['path'], error=str(error)))
        else:
            if current != row:
                changes.append(dict(path=row['path'], current=current))
    return changes


def require_package_inventory(package, expected):
    current = {p for p in package.rglob('*') if p.is_file() or p.is_symlink()}
    require(current == expected, 'Package source inventory changed: ' +
            repr(sorted(str(p) for p in current.symmetric_difference(expected))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['focused', 'full', 'package', 'native', 'rust'])
    parser.add_argument('repo', type=Path)
    parser.add_argument('source_sha')
    parser.add_argument('runner_sha')
    parser.add_argument('library', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    require_fresh(args.output)
    repo, library, output = args.repo.resolve(), args.library.resolve(), args.output.resolve()
    require_fresh(output)
    driver = 'benchmarks/r-dibble-dplyr/run-expression-checks.py'
    git = lambda *a: subprocess.check_output(['git', '-C', str(repo), *a])
    require(Path(__file__).read_bytes() == git('show', args.runner_sha + ':' + driver),
            'Driver differs from the exact runner commit')
    require(git('rev-parse', args.source_sha + ':r-package/dtatools') ==
            git('rev-parse', args.runner_sha + ':r-package/dtatools'),
            'Runner package source differs from qualified installation')
    output.mkdir(parents=True)
    source = output / 'source'
    archive = output / 'source.tar'
    subprocess.run(['git', '-C', str(repo), 'archive', '--format=tar', '--output=' + str(archive),
                    args.runner_sha], check=True)
    with tarfile.open(archive) as tar:
        for item in tar.getmembers():
            require(not Path(item.name).is_absolute() and '..' not in Path(item.name).parts and
                    (item.isfile() or item.isdir()), 'Unexpected archive member: ' + item.name)
        tar.extractall(source, filter='data')
    entries = git('ls-tree', '-r', '-z', args.runner_sha).split(b'\0')
    expected = set()
    for entry in entries:
        if not entry:
            continue
        metadata, raw = entry.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split()
        path = source / os.fsdecode(raw)
        expected.add(path)
        content = path.read_bytes()
        observed = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        require(kind == 'blob' and observed == blob and
                bool(path.stat().st_mode & 0o111) == (mode == '100755'),
                'Source export differs from Git: ' + str(path))
    require({p for p in source.rglob('*') if p.is_file()} == expected, 'Source inventory differs from Git')
    # All installed site packages are bound so optional tests cannot introduce
    # an unrecorded transitive dependency. System dylibs/SDK and the complete
    # Python process closure are not frozen by this check runner.
    rroot = Path('/opt/homebrew/Cellar/r/4.6.1')
    site = Path('/opt/homebrew/lib/R/4.6/site-library')
    inputs = {Path(__file__).resolve(), archive, *expected}
    for directory in [rroot, site, library / 'dtatools']:
        require(directory.is_dir(), 'Missing input tree: ' + str(directory))
        inputs.update(p for p in directory.rglob('*') if p.is_file())
    tools = {name: Path(shutil.which(name)).resolve(strict=True) for name in
             ['git', 'cargo', 'rustc', 'clang', 'cc', 'make', 'tar', 'sh', 'sed', 'uname', 'ar', 'ranlib', 'ld', 'xcrun', 'bun', 'R', 'Rscript']}
    inputs.update(tools.values())
    rust_root = tools['rustc'].parent.parent
    inputs.update(p for p in rust_root.rglob('*') if p.is_file())
    for config in [Path('/Users/jmb/.R/Makevars'), Path('/Users/jmb/.cargo/config'), Path('/Users/jmb/.cargo/config.toml')]:
        if config.is_file():
            inputs.add(config)
    if args.phase == 'native':
        inputs.update(repo/file for file in ['benchmarks/r-reference-mutation/owned-atoms.R', 'benchmarks/r-dibble-dplyr/helpers.R'])
    before = [identity(p) for p in sorted(inputs)]
    package_root = source/'r-package/dtatools'
    package_inventory = {p for p in expected if p.is_relative_to(package_root)}
    write(output / 'inputs-before.json', dict(source_sha=args.source_sha,
        runner_sha=args.runner_sha, phase=args.phase, inputs=before,
        scope='Exact Git sources plus complete visible R/site/candidate library files. '
              'R/Rust/tool executables are bound; external OS dylibs, full SDK and Python closure are not frozen.'))
    environment = dict(os.environ)
    environment.update(R_LIBS=str(library), R_LIBS_SITE=str(site),
        R_LIBS_USER=str(output / 'nonexistent-user-library'),
        R_PROFILE_USER='/dev/null', R_ENVIRON_USER='/dev/null', CARGO_NET_OFFLINE='true')
    for variable in ['R_HOME', 'R_ARCH', 'DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH']:
        environment.pop(variable, None)
    records = []
    def guard():
        changes = input_changes(before)
        require(not changes, 'Bound inputs changed: ' + repr(changes))
        require_package_inventory(package_root, package_inventory)
    def run(label, command, cwd=source, env=None):
        guard()
        record = dict(label=label, command=command, cwd=str(cwd),
                      started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        with (output / (label + '.log')).open('x') as stream:
            record['exit_code'] = subprocess.run(command, cwd=cwd, env=env or environment,
                stdout=stream, stderr=subprocess.STDOUT).returncode
        record['completed_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        record['log'] = identity(output / (label + '.log'))
        records.append(record)
        write(output / (label + '-command.json'), record)
        guard()
        print(label, record['exit_code'], flush=True)
        require(record['exit_code'] == 0, 'Check failed: ' + label)
    status = 'failed'
    changed = []
    try:
        run('preflight', ['Rscript', '--vanilla', 'benchmarks/r-dibble-dplyr/expression-preflight.R',
            str(library), args.source_sha, str(source), str(output)])
        if args.phase in ('focused', 'full'):
            pattern = 'dibble|owned|reference|group|mutat|replac' if args.phase == 'focused' else 'all'
            run('tests', ['Rscript', '--vanilla', 'benchmarks/r-dibble-dplyr/expression-checks.R',
                str(library), args.source_sha, str(source), str(output), pattern])
            bound = {row['resolved'] for row in before}
            with (output / 'namespaces.tsv').open() as stream:
                for row in csv.DictReader(stream, delimiter='\t'):
                    require(str((Path(row['path']) / 'DESCRIPTION').resolve()) in bound,
                            'Unbound namespace: ' + row['name'])
        elif args.phase == 'package':
            for label, file in [('archive-unit', 'test_check_r_package_archive.py'),
                                ('vendor-unit', 'test_check_r_cargo_vendor.py'),
                                ('vendor-rebuild-unit', 'test_rebuild_r_vendor.py')]:
                run(label, ['python3', '-m', 'unittest', 'discover', '-s', 'scripts', '-p', file, '-v'])
            for label, file in [('vendor', 'check-r-cargo-vendor.sh'),
                                ('rust-source-hash', 'test-rust-source-hash.sh')]:
                run(label, ['sh', 'scripts/' + file])
            for label, file in [('haven', 'scripts/test-haven-helper-interop.R'),
                                ('labelled', 'scripts/test-labelled-interop.R'),
                                ('haven-conformance', 'scripts/test-haven-conformance.R'),
                                ('corpus-framework', 'benchmarks/r-corpus-performance/test-framework.R')]:
                run(label, ['Rscript', '--vanilla', file])
            run('roxygen', ['Rscript', '--vanilla', '-e',
                'stopifnot(as.character(packageVersion("roxygen2")) == read.dcf("DESCRIPTION", "Config/roxygen2/version")[[1L]]); roxygen2::roxygenise(".", load_code="source")'],
                source/'r-package/dtatools')
            env = dict(environment, DTA_REQUIRE_R_CONFORMANCE='1')
            run('conformance', ['sh', 'scripts/conformance.sh'], env=env)
            run('build', ['R', 'CMD', 'build', str(source/'r-package/dtatools')], output)
            version = next(line.split(': ', 1)[1] for line in (source/'r-package/dtatools/DESCRIPTION').read_text().splitlines() if line.startswith('Version: '))
            package = output / ('dtatools_' + version + '.tar.gz')
            run('archive', ['sh', 'scripts/check-r-package-archive.sh', str(package)])
            # Keep this archive's complete check tree even when check fails.
            # The shared conformance gate also checks its own temporary copy.
            run('check', ['R', 'CMD', 'check', '--no-manual', str(package)], output)
            binary = output/'binary'
            binary.mkdir()
            binary_library = binary/'library'
            binary_library.mkdir()
            run('binary', ['R', 'CMD', 'INSTALL', '--build', '--clean', '--library='+str(binary_library), str(package)], binary)
            expected_notice = (source/'r-package/dtatools/inst/NOTICE').read_bytes()
            require((library/'dtatools/NOTICE').read_bytes() == expected_notice, 'Installed NOTICE differs')
            require((binary_library/'dtatools/NOTICE').read_bytes() == expected_notice, 'Binary installed NOTICE differs')
            for bundle in [package, binary/('dtatools_' + version + '.tgz')]:
                with tarfile.open(bundle) as tar:
                    notice = next(member for member in tar.getmembers() if member.name in ('dtatools/inst/NOTICE', 'dtatools/NOTICE'))
                    require(tar.extractfile(notice).read() == expected_notice, 'Packaged NOTICE differs')
        elif args.phase == 'native':
            env = dict(environment, DTATOOLS_BENCHMARK_CHILD='1', DTATOOLS_BENCHMARK_LIBRARY=str(library),
                DTATOOLS_BENCHMARK_SHA=args.source_sha, DTATOOLS_BENCHMARK_STATE='clean')
            run('native', ['Rscript', '--vanilla', 'benchmarks/r-reference-mutation/run.R',
                '--markdown='+str(output/'native.md')], env=env)
            atom = output/'atoms'
            atom.mkdir()
            for file in ['benchmarks/r-reference-mutation/owned-atoms.R', 'benchmarks/r-dibble-dplyr/helpers.R']:
                require((repo/file).read_bytes() == (source/file).read_bytes(), 'Native runner differs from committed source')
            run('native-atoms', ['Rscript', '--vanilla', 'benchmarks/r-reference-mutation/owned-atoms.R',
                str(library), args.source_sha, str(atom)], repo)
            run('rename', ['Rscript', '--vanilla', 'benchmarks/r-dibble-dplyr/check-rename-allocation.R', str(library)])
        else:
            for label, command in [
                ('fmt', ['cargo', 'fmt', '--all', '--', '--check']),
                ('clippy', ['cargo', 'clippy', '--workspace', '--all-targets', '--locked', '--', '-D', 'warnings']),
                ('tests', ['cargo', 'test', '--workspace', '--all-targets', '--locked']),
                ('docs', ['cargo', 'doc', '--workspace', '--locked', '--no-deps']),
                ('package', ['cargo', 'package', '-p', 'dta-tools', '--locked', '--allow-dirty'])]:
                run(label, command, env=dict(environment, RUSTDOCFLAGS='-D warnings'))
        status = 'complete'
    finally:
        changed = input_changes(before)
        try:
            require_package_inventory(package_root, package_inventory)
        except RuntimeError as error:
            changed.append(dict(package_inventory_error=str(error)))
        if changed:
            status = 'failed'
        write(output/'execution-result.json', dict(status=status, records=records, changed_inputs=changed))
        # Deliberately list before opening either of these two destinations.
        products = [identity(p) for p in sorted(output.rglob('*')) if p.is_file()
                    and p not in (output/'manifest.json', output/'receipt.json')]
        write(output/'manifest.json', dict(products=products, excluded_self='manifest.json', excluded_receipt='receipt.json'))
        write(output/'receipt.json', dict(status=status, source_sha=args.source_sha,
            runner_sha=args.runner_sha, changed_inputs=changed, manifest=identity(output/'manifest.json')))
    require(status == 'complete' and not changed, 'Qualification incomplete; inspect retained output')
    print('Receipt SHA256', digest(output/'receipt.json'))


if __name__ == '__main__':
    main()

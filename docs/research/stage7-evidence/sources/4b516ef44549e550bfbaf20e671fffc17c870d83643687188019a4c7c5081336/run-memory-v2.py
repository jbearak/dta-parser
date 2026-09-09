#!/usr/bin/env python3
"""Run one Stage7 retained-memory case in a fresh R child with whole-child RSS."""
import argparse
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def identity(path):
    return dict(path=str(path), resolved=str(path.resolve(strict=True)),
                bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('runner_sha')
    parser.add_argument('installation', type=Path)
    parser.add_argument('source_sha')
    parser.add_argument('output', type=Path)
    parser.add_argument('--iterations', type=int, default=7)
    parser.add_argument('--rows', default='100000')
    parser.add_argument('--receipt-sha256', required=True)
    parser.add_argument('--script', type=Path, required=True)
    parser.add_argument('--routes', choices=['public', 'predecessor_safe_reference'], default='public')
    parser.add_argument('--workload', required=True, choices=['group_modify_identity', 'group_nest', 'nest_by'])
    parser.add_argument('--r-root', type=Path, default=Path('/opt/homebrew/Cellar/r/4.6.1'))
    parser.add_argument('--rscript', type=Path, default=Path('/opt/homebrew/Cellar/r/4.6.1/bin/Rscript'))
    parser.add_argument('--site', type=Path, default=Path('/opt/homebrew/lib/R/4.6/site-library'))
    args = parser.parse_args()
    repo, install = args.repo.resolve(strict=True), args.installation.resolve(strict=True)
    output = args.output.absolute()
    require(output == output.resolve() and not output.exists(), 'Fresh canonical output required')
    require(not output.is_relative_to(repo) and not output.is_relative_to(install),
            'Output overlaps a protected input')
    require(args.rows.isdecimal() and int(args.rows) >= 256, 'One row count of at least256 required')
    require(all(len(x) == 40 and all(c in '0123456789abcdef' for c in x)
                for x in [args.source_sha, args.runner_sha]), 'Full source hashes required')
    root = Path(__file__).resolve().parent
    workload = args.script.resolve(strict=True)
    support = root / 'support-v2'
    support_names = ['validation-v2.R', 'workloads-v1.R', 'reference-v1.R', 'schemas.R']
    support_paths = [support / name for name in support_names]
    require(not output.is_relative_to(root), 'Output must be outside the prepared source directory')
    output.mkdir(parents=True)
    before, after, records = [], [], []
    failure, status = None, 'failed'
    binding_complete = False
    source = output / 'source'
    library = install / 'library'
    rroot = args.r_root.absolute()
    site = args.site.absolute()
    rscript = args.rscript.absolute()  # Preserve the selected invocation basename.
    git = Path('/opt/homebrew/bin/git')
    try:
        require(rroot == rroot.resolve(strict=True) and site == site.resolve(strict=True),
                'Canonical runtime/site roots required')
        approved = {}

        def bind(path, expected=None):
            observed = identity(path)
            if expected is not None:
                require(observed == expected, 'Accepted identity changed: ' + str(path))
            previous = approved.get(str(path))
            require(previous is None or previous == observed, 'Input was rebound: ' + str(path))
            approved[str(path)] = observed
            return observed

        def read_json(path, expected=None):
            pinned = bind(path, expected)
            value = json.loads(path.read_text())
            bind(path, pinned)
            return value

        selected_time = bind(Path('/usr/bin/time'))
        selected_rscript = bind(rscript)
        bind(Path(selected_rscript['resolved']))
        require(Path(selected_rscript['resolved']).is_relative_to(rroot),
                'Selected Rscript is outside bound runtime')
        require(not output.is_relative_to(rroot) and not output.is_relative_to(site),
                'Output overlaps a runtime root')
        receipt = install / 'completed-receipt.json'
        pinned_receipt = bind(receipt)
        require(pinned_receipt['sha256'] == args.receipt_sha256,
                'Installation receipt differs from accepted identity')
        observed = read_json(receipt, pinned_receipt)
        require(observed['status'] == 'complete' and observed['revision'] == args.source_sha,
                'Wrong or incomplete installation')
        manifest = install / 'output-manifest.json'
        installed_index = install / 'installed-files.json'
        products = read_json(manifest, observed['manifest'])['products']
        installed_rows = [row for row in products if row['path'] == str(installed_index)]
        require(len(installed_rows) == 1, 'Missing or duplicate accepted installed index')
        expected_install = read_json(installed_index, installed_rows[0])['files']
        expected_paths = {row['path'] for row in expected_install}
        require(len(expected_paths) == len(expected_install) and len(expected_paths) > 0,
                'Installed index paths must be unique and nonempty')
        for row in expected_install:
            require(Path(row['path']).is_relative_to(library / 'dtatools'), 'Installed path outside package')
            bind(Path(row['path']), row)
        selected_git = bind(git)
        bind(git.resolve(strict=True))
        source_environment = dict(os.environ)
        write(output / 'git-selection.json', dict(invocation=selected_git,
            canonical=identity(git.resolve(strict=True)), PATH=source_environment.get('PATH', '')))

        def run_git(tail):
            command = [str(git), '-C', str(repo)] + tail
            number = len(records)
            record = dict(requested=['git', '-C', str(repo)] + tail, command=command,
                git=selected_git, PATH=source_environment.get('PATH', ''),
                started_utc=now(), returncode=None, error=None)
            records.append(record)
            write(output / ('git-%02d-before.json' % number), record)
            try:
                bind(git, selected_git)
                with (output / ('git-%02d.stderr' % number)).open('x') as errors:
                    result = subprocess.run(command, env=source_environment,
                                            stdout=subprocess.PIPE, stderr=errors)
                (output / ('git-%02d.stdout' % number)).write_bytes(result.stdout)
                record.update(returncode=result.returncode, bytes=len(result.stdout),
                              sha256=hashlib.sha256(result.stdout).hexdigest())
                bind(git, selected_git)
                require(result.returncode == 0, 'Git source command failed')
                return result.stdout
            except BaseException as error:
                record['error'] = dict(type=type(error).__name__, message=str(error))
                raise
            finally:
                record['completed_utc'] = now()
                write(output / ('git-%02d-result.json' % number), record)

        package_tree = run_git(['rev-parse', args.source_sha + ':r-package/dtatools']).decode().strip()
        require(package_tree == observed['package_tree'], 'Installed source package tree differs')
        source.mkdir()
        helpers = ['helpers.R', 'owned-double-helpers.R', 'owned-atomic-helpers.R',
                   'owned-atomic.R', 'owned-atomic-memory.R']
        selected = [Path(__file__).resolve(), root / 'entry-v2.R', workload,
                    root / 'README-memory-v2.md', receipt, install / 'installed-files.json',
                    install / 'output-manifest.json', rscript, git, git.resolve(),
                    Path(sys.executable).resolve(), Path(sys.orig_argv[0]).absolute()]
        selected.append(rscript.resolve(strict=True))
        selected.extend(support_paths)
        selected.append(Path('/usr/bin/time'))
        schema_pin = 'd44ee08e5c981fd9490bfbd4354dabc766eece6d6dbd7192cf608cfb8efebe33'
        require(bind(support / 'schemas.R')['sha256'] == schema_pin, 'Fixed predecessor schema changed')
        for path in selected:
            bind(path)
        for name in helpers:
            rel = 'benchmarks/r-dibble-dplyr/' + name
            data = run_git(['show', args.runner_sha + ':' + rel])
            destination = source / rel
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            bind(destination)
            selected.append(destination)
        copies = [(root / 'entry-v2.R', 'entry-v2.R'), (workload, 'selected-workload.R'),
                  (Path(__file__), 'run-memory-v2.py'), (root / 'README-memory-v2.md', 'README-memory-v2.md')]
        copies.extend((path, 'stage7-support/' + path.name) for path in support_paths)
        for original, name in copies:
            original = original.resolve(strict=True)
            pinned_source = bind(original)
            data = original.read_bytes()
            bind(original, pinned_source)
            destination = source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            destination.chmod(int(pinned_source['mode'], 8))
            copied = bind(destination)
            require(all(copied[key] == pinned_source[key] for key in ('sha256', 'bytes', 'mode')),
                    'Exported source copy differs from pinned original')
            selected.extend([original, destination])
        write(output / 'source-exports.json', records)
        roots = [rroot, site, library / 'dtatools']

        def inventory():
            paths = set(selected)
            for directory in roots:
                require(directory.is_dir(), 'Missing runtime root ' + str(directory))
                paths.update(p for p in directory.rglob('*')
                             if (p.is_file() or p.is_symlink()) and not p.is_dir())
            return [identity(p) for p in sorted(paths)]

        require(identity(git) == selected_git, 'Selected Git changed before complete inventory')
        before = inventory()
        bound_by_path = {row['path']: row for row in before}
        require(all(bound_by_path.get(path) == row for path, row in approved.items()),
                'Previously validated identity changed before complete binding')
        write(output / 'inputs-before.json', before)
        write(output / 'accepted-input-identities.json', sorted(approved.values(), key=lambda row: row['path']))
        current_install = {row['path'] for row in before
                           if Path(row['path']).is_relative_to(library / 'dtatools')}
        require(current_install == expected_paths, 'Installed package membership differs')
        binding_complete = True
        write(output / 'installation-comparison.json', dict(receipt=identity(receipt),
            manifest=identity(manifest), installed_index=identity(installed_index),
            files=len(expected_paths), source=args.source_sha, package_tree=package_tree))
        environment = dict(os.environ)
        environment.update(R_LIBS=str(library), R_LIBS_SITE=str(site),
            R_LIBS_USER=str(output / 'absent-user-library'), R_PROFILE_USER='/dev/null',
            R_ENVIRON_USER='/dev/null', DTA_ROW_SCRIPT=str(source / 'selected-workload.R'),
            DTA_ROW_ISOLATION_SCRIPT='', DTA_STAGE7_SUPPORT=str(source / 'stage7-support'),
            DTA_STAGE7_ROUTES=args.routes, DTA_STAGE7_MEMORY_WORKLOAD=args.workload,
            DTA_ROW_OUTER_OUTPUT=str(output))
        for name in ['R_HOME', 'R_ARCH', 'DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH',
                     'DYLD_FRAMEWORK_PATH']:
            environment.pop(name, None)
        results = output / 'results'
        results.mkdir()
        command = ['/usr/bin/time', '-l', str(rscript), '--vanilla', str(source / 'entry-v2.R'), str(library),
                   str(results), args.source_sha, str(args.iterations), args.rows]
        record = dict(command=command, cwd=str(source), PATH=environment['PATH'],
                      selected_rscript=selected_rscript, selected_time=selected_time,
                      python=identity(Path(sys.executable)),
                      python_invocation=sys.orig_argv, started_utc=now())
        record.update(returncode=None, error=None)
        write(output / 'command-before.json', record)
        try:
            require(inventory() == before, 'Selected input changed before R launch')
            with (output / 'runner.log').open('x') as log:
                result = subprocess.run(command, cwd=source, env=environment,
                                        stdout=log, stderr=subprocess.STDOUT)
            record['returncode'] = result.returncode
        except BaseException as error:
            record['error'] = dict(type=type(error).__name__, message=str(error))
            raise
        finally:
            record['completed_utc'] = now()
            write(output / 'command-result.json', record)
        require(record['returncode'] == 0, 'R Stage7 workload failed; retained raw log and partial products')
        require(not (output / 'runtime-recording-error.txt').exists(),
                'Runtime recording failed; retained explicit error marker')
        rss = re.findall(r'^\s*(\d+)\s+maximum resident set size\s*$', (output / 'runner.log').read_text(), re.MULTILINE)
        require(len(rss) == 1, 'Missing or duplicate whole-child RSS record')
        write(output / 'whole-child-rss.json', dict(bytes=int(rss[0]), workload=args.workload, rows=int(args.rows), route=args.routes, scope='macOS time -l maximum RSS for the whole R child, including setup, validation and runtime recording; not individual-operation peak'))
        bound = {row['resolved'] for row in before}
        with (output / 'namespaces.tsv').open() as stream:
            reader = csv.DictReader(stream, delimiter='\t')
            require(reader.fieldnames == ['name', 'path'], 'Invalid namespace schema')
            namespaces = list(reader)
        namespace_names = [row['name'] for row in namespaces]
        require(len(set(namespace_names)) == len(namespace_names) and
                {'base', 'dtatools', 'bench'} <= set(namespace_names),
                'Missing or duplicate required namespaces')
        for row in namespaces:
            description = Path(row['path']) / 'DESCRIPTION'
            require(str(description.resolve(strict=True)) in bound,
                    'Unbound namespace ' + row['name'])
            package_names = re.findall(r'^Package:[ \t]*(\S+)[ \t]*$', description.read_text(), re.MULTILINE)
            require(package_names == [row['name']], 'Namespace name differs from DESCRIPTION Package')
            if row['name'] == 'dtatools':
                require(Path(row['path']).resolve(strict=True) == (library / 'dtatools').resolve(strict=True),
                        'Wrong dtatools namespace location')
        with (output / 'dlls.tsv').open() as stream:
            reader = csv.DictReader(stream, delimiter='\t')
            require(reader.fieldnames == ['name', 'path'], 'Invalid DLL schema')
            dlls = list(reader)
        require(len({row['name'] for row in dlls}) == len(dlls) and dlls,
                'Empty or duplicate DLL names')
        non_file = []
        for row in dlls:
            if row['name'] == 'base' and row['path'] == 'base':
                non_file.append(row)
            else:
                require(str(Path(row['path']).resolve()) in bound,
                        'Unbound registered file DLL ' + row['name'])
        write(output / 'runtime-coverage.json', dict(namespaces=len(namespaces),
            file_dlls=len(dlls) - len(non_file), non_file=non_file,
            scope='Selected parent R namespace and DLL files, not full process/image closure'))
        after = inventory()
        require(before == after, 'Selected inputs or membership changed')
        status = 'complete'
    except BaseException as error:
        failure = dict(type=type(error).__name__, message=str(error))
        raise
    finally:
        if before and not after:
            try:
                after = inventory()
            except BaseException as error:
                if failure is None:
                    failure = dict(type=type(error).__name__, message=str(error))
        write(output / 'inputs-after.json', after)
        write(output / 'result.json', dict(status=status, error=failure,
            input_binding_complete=binding_complete, inputs_unchanged=binding_complete and before == after,
            performance_acceptance=False,
            source_sha=args.source_sha, runner_sha=args.runner_sha, installation=str(install),
            scope='Selected Stage7 retained-memory workload execution; overall performance acceptance and full subprocess closure are separate'))
        products = [identity(p) for p in sorted(output.rglob('*')) if p.is_file()]
        write(output / 'products.json', dict(products=products,
                                           excluded=['products.json', 'receipt.json']))
        write(output / 'receipt.json', dict(status=status, result=identity(output / 'result.json'),
                                           products=identity(output / 'products.json')))


if __name__ == '__main__':
    main()

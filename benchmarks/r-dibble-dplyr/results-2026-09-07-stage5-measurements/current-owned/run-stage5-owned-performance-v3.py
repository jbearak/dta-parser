"""Coordinate unchanged owned/read benchmarks with retained outer integrity records.

Run only in a quiet window. Per-command hashing occurs outside child timing.
The original unexecuted coordinator is preserved separately.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPO = Path('/private/tmp/dta-direct-stage4')
VALIDATION = Path('/private/tmp/dta-direct-stage5-validation')
OUTPUT = VALIDATION / 'root-stage5-owned-performance-a2d8b6a'
CANDIDATE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
BASELINE = 'f622f1ddba04b2bb7ac07415faccf2b417aab0e6'
RUNNER = CANDIDATE
RELATIVE = Path('benchmarks/r-dibble-dplyr')
NAMES = ['helpers.R', 'owned-double-helpers.R', 'owned-atomic-helpers.R',
         'owned-double.R', 'owned-double-memory.R', 'owned-atomic.R',
         'owned-atomic-memory.R', 'owned-heap.R', 'run-owned-qualification.py',
         'run-atomic-qualification.py', 'run-heap-qualification.py']
COMPARATORS = ['compare-atomic.py', 'compare-double.py', 'compare-heap-stage5-v3.py']
LIBRARIES = [('baseline', BASELINE, VALIDATION / 'root-baseline-f622f1d/library'),
             ('candidate', CANDIDATE, VALIDATION / 'implementation/candidate-combined-01/library')]


def require(value, message):
    if not value:
        raise RuntimeError(message)


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            result.update(block)
    return result.hexdigest()


def identity(path):
    resolved = path.resolve(strict=True)
    stat = resolved.stat()
    require(resolved.is_file(), 'Not a regular file: ' + str(path))
    return dict(path=str(path), resolved=str(resolved), bytes=stat.st_size,
                mode=oct(stat.st_mode & 0o777), sha256=sha(resolved))


def write(path, value):
    content = json.dumps(value, indent=2, sort_keys=True) + '\n'
    with path.open('x') as stream:
        stream.write(content)


def require_fresh(path):
    require(not path.exists() and not path.is_symlink(), 'Fresh output required: ' + str(path))


def input_changes(before):
    changes = []
    for item in before:
        try:
            current = identity(Path(item['path']))
        except (OSError, RuntimeError) as error:
            changes.append(dict(path=item['path'], error=str(error)))
        else:
            if current != item:
                changes.append(dict(path=item['path'], current=current))
    return changes


def inventory(path):
    return {str(p) for p in path.rglob('*') if p.is_file() or p.is_symlink()}


def inventory_changes(before):
    return [dict(directory=directory, difference=sorted(current.symmetric_difference(paths)))
            for directory, paths in before.items()
            if (current := inventory(Path(directory))) != paths]


def main():
    require_fresh(OUTPUT)
    tools = {name: Path(shutil.which(name)).resolve(strict=True) for name in
             ['git', 'Rscript', 'python3', 'sh', 'shasum']}
    rroot = Path('/opt/homebrew/Cellar/r/4.6.1')
    site = Path('/opt/homebrew/lib/R/4.6/site-library')
    require(tools['Rscript'] == (rroot/'bin/Rscript').resolve(strict=True), 'Unexpected Rscript')
    inputs = {Path(__file__).resolve(), Path(sys.executable).resolve(strict=True),
              Path('/usr/bin/time'), Path('/usr/bin/perl'), *tools.values()}
    for name in NAMES:
        path = REPO / RELATIVE / name
        expected = subprocess.check_output([str(tools['git']), 'show', f'{RUNNER}:{RELATIVE/name}'], cwd=REPO)
        require(path.read_bytes() == expected, 'Uncommitted runner input: ' + name)
        inputs.add(path)
    inputs.update(VALIDATION/name for name in COMPARATORS)
    trees = [rroot, site, *(library/'dtatools' for _, _, library in LIBRARIES)]
    for tree in trees:
        require(tree.is_dir(), 'Missing installed input: ' + str(tree))
        inputs.update(p for p in tree.rglob('*') if p.is_file())
    before = [identity(path) for path in sorted(inputs)]
    tree_inventory = {str(tree): inventory(tree) for tree in trees}
    OUTPUT.mkdir()
    environment = dict(os.environ)
    environment.update(R_LIBS='', R_LIBS_SITE=str(site),
        R_LIBS_USER=str(OUTPUT/'nonexistent-user-library'),
        R_PROFILE_USER='/dev/null', R_ENVIRON_USER='/dev/null')
    for name in ['R_HOME', 'R_ARCH', 'DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH', 'DYLD_FRAMEWORK_PATH']:
        environment.pop(name, None)
    write(OUTPUT/'input-identities.json', dict(candidate_source=CANDIDATE,
        baseline_source=BASELINE, runner_source=RUNNER, inputs=before,
        inventories={path: sorted(files) for path, files in tree_inventory.items()},
        environment={name: environment[name] for name in
            ['R_LIBS', 'R_LIBS_SITE', 'R_LIBS_USER', 'R_PROFILE_USER', 'R_ENVIRON_USER']},
        scope='Exact benchmark sources and complete visible installed R/site/baseline/candidate package files. '
              'Python and selected subprocess executables are bound; full Python/OS dynamic-library closures are not frozen.'))
    commands = []
    consumed = []
    consumed_inventory = {}

    def freeze(directory, label, complete):
        observed = [identity(Path(p)) for p in sorted(inventory(directory))]
        write(OUTPUT/(label+'-products.json'), dict(products=observed))
        existing = {item['path'] for item in consumed}
        consumed.extend(item for item in observed if item['path'] not in existing)
        if complete:
            consumed_inventory[str(directory)] = inventory(directory)

    def guard():
        changes = input_changes(before + consumed)
        differences = inventory_changes(tree_inventory | consumed_inventory)
        require(not changes and not differences, 'Changed bound inputs: ' + repr(changes + differences))

    def run(name, command):
        guard()
        log = OUTPUT/(name+'.log')
        record = dict(name=name, command=command, cwd=str(REPO), started_utc=stamp())
        with log.open('x') as stream:
            record['exit_code'] = subprocess.run(command, cwd=REPO, env=environment,
                stdout=stream, stderr=subprocess.STDOUT).returncode
        record.update(finished_utc=stamp(), log=identity(log))
        commands.append(record)
        write(OUTPUT/(name+'-command.json'), record)
        guard()
        print(name, 'exit', record['exit_code'], flush=True)
        require(record['exit_code'] == 0, 'Qualification failed; retained evidence: ' + str(log))

    status = 'failed'
    failure = None
    try:
        for family, driver in [('atomic', 'run-atomic-qualification.py'), ('double', 'run-owned-qualification.py')]:
            for phase in ['operations', 'memory']:
                for mode, revision, library in LIBRARIES:
                    directory = OUTPUT/f'{family}-{mode}'
                    if phase == 'memory':
                        # This command extends only the child manifest and adds
                        # memory logs. Check its prior manifest before allowing
                        # that documented update; all other files stay frozen.
                        guard()
                        consumed[:] = [item for item in consumed
                            if item['path'] != str(directory/'root-manifest.json')]
                        consumed_inventory.pop(str(directory))
                    run(f'{family}-{mode}-{phase}', [sys.executable, str(REPO/RELATIVE/driver),
                        phase, str(REPO), str(directory), str(library), revision, RUNNER, mode])
                    freeze(directory, f'{family}-{mode}-{phase}', True)
        for mode, revision, library in LIBRARIES:
            run(f'heap-{mode}', [sys.executable, str(REPO/RELATIVE/'run-heap-qualification.py'),
                str(REPO), str(OUTPUT/f'heap-{mode}'), str(library), revision, RUNNER, mode])
            freeze(OUTPUT/f'heap-{mode}', f'heap-{mode}', True)
        write(OUTPUT/'comparison-inputs.json', dict(inputs=consumed,
            inventories={path: sorted(files) for path, files in consumed_inventory.items()}))
        for family, comparator in [('atomic', 'compare-atomic.py'), ('double', 'compare-double.py'),
                                   ('heap', 'compare-heap-stage5-v3.py')]:
            command = [sys.executable, str(VALIDATION/comparator)]
            if family == 'heap':
                command.append(str(REPO))
            command.extend(str(OUTPUT/name) for name in
                [f'{family}-baseline', f'{family}-candidate', f'{family}-comparison'])
            run('compare-'+family, command)
            freeze(OUTPUT/f'{family}-comparison', 'compare-'+family, True)
        status = 'complete'
    except BaseException as error:
        failure = dict(type=type(error).__name__, message=str(error))
        raise
    finally:
        changes = input_changes(before + consumed)
        changes.extend(inventory_changes(tree_inventory | consumed_inventory))
        if changes:
            status = 'failed'
        write(OUTPUT/'execution-result.json', dict(status=status, commands=commands,
            changed_inputs=changes, failure=failure, candidate_source=CANDIDATE, baseline_source=BASELINE,
            runner_source=RUNNER, scope='Comparison flags require assessment; completed execution is not a performance acceptance decision.'))
        products = [identity(path) for path in sorted(OUTPUT.rglob('*')) if path.is_file()
            and path not in (OUTPUT/'output-manifest.json', OUTPUT/'completed-receipt.json')]
        write(OUTPUT/'output-manifest.json', dict(products=products,
            excluded_self='output-manifest.json', excluded_receipt='completed-receipt.json'))
        write(OUTPUT/'completed-receipt.json', dict(status=status, changed_inputs=changes,
            candidate_source=CANDIDATE, baseline_source=BASELINE, runner_source=RUNNER,
            manifest=identity(OUTPUT/'output-manifest.json')))
    require(status == 'complete', 'Paired matrices failed; inspect retained evidence')
    print('All paired matrices and guarded comparisons complete.', flush=True)


if __name__ == '__main__':
    main()

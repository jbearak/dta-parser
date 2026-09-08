"""Compare completed, independently audited expression matrices.

This derives comparison tables; it does not run operations or decide overall
performance acceptance. Keep both completed input directories idle.
"""
import csv
import datetime
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
BASELINE = 'f622f1ddba04b2bb7ac07415faccf2b417aab0e6'
CANDIDATE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
# Both measurements must use the same pinned launcher and separately bound R
# command. All remaining common input identities must match as well.
LAUNCHERS = {
    BASELINE: dict(
        path='/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14',
        resolved='/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14',
        bytes=33816, mode='0o755',
        sha256='8e8f1b256a299fe22e6cfe0dad6801ae8f0c62c7cfef844fbc2db92c03cfe32d'),
    CANDIDATE: dict(
        path='/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14',
        resolved='/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14',
        bytes=33816, mode='0o755',
        sha256='8e8f1b256a299fe22e6cfe0dad6801ae8f0c62c7cfef844fbc2db92c03cfe32d'),
}

KEYS = ['rows', 'columns', 'groups', 'kind', 'operation']
MODES = ['direct', 'safe_reference']
METRICS = [
    'median_ms', 'bench_allocated_bytes', 'iterations', 'gc_count',
    'r_allocated_bytes', 'r_largest_allocation_bytes', 'native_owned_capture_bytes',
    'native_compact_copy_bytes', 'native_staged_new_bytes', 'native_old_journal_bytes',
    'native_native_scratch_allocated_bytes', 'native_mutation_target_copy_bytes',
]
SCHEMA = KEYS + ['mode', 'actual_input_columns'] + METRICS
REQUIRED_COMMON = [ROOT / 'measure-v4.py', ROOT / 'measure-v4.R', ROOT / 'cases-v10.R',
    Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R'),
    Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/owned-double-helpers.R')]



def require(value, message):
    if not value:
        raise RuntimeError(message)


def identity(path):
    target = path.resolve(strict=True)
    info = target.stat()
    require(target.is_file(), 'Expected regular file: ' + str(path))
    digest = hashlib.sha256()
    with target.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            digest.update(block)
    return dict(path=str(path), resolved=str(target), bytes=info.st_size,
                mode=oct(info.st_mode & 0o777), sha256=digest.hexdigest())


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def changes(inputs):
    result = []
    for item in inputs:
        try:
            current = identity(Path(item['path']))
        except (OSError, RuntimeError) as error:
            result.append(dict(path=item['path'], error=str(error)))
        else:
            if current != item:
                result.append(dict(path=item['path'], current=current))
    return result


def load_completed(name, inputs, inventories):
    folder = ROOT / name
    receipt_path = ROOT / (name + '-receipt.json')
    receipt_binding = identity(receipt_path)
    inputs.append(receipt_binding)
    receipt = json.loads(receipt_path.read_text())
    require(receipt.get('accepted') is True, 'Unaccepted input: ' + name)
    manifest = folder / 'manifest.json'
    manifest_binding = identity(manifest)
    inputs.append(manifest_binding)
    require(manifest_binding == receipt['manifest'], 'Changed manifest: ' + name)
    products = json.loads(manifest.read_text())['products']
    paths = [item['path'] for item in products]
    require(len(paths) == len(set(paths)), 'Duplicate product: ' + name)
    require(all(Path(path).parent == folder for path in paths), 'Unexpected product scope')
    observed = {str(path) for path in folder.iterdir()}
    expected = set(paths) | {str(manifest)}
    require(observed == expected and not changes(products), 'Changed products: ' + name)
    inventories[str(folder)] = sorted(observed)
    inputs.extend(products)
    require(not changes([receipt_binding, manifest_binding]), 'Receipt or manifest changed while reading')
    return folder, receipt


def load_matrix(name, audit_name, source, inputs, inventories):
    folder, receipt = load_completed(name, inputs, inventories)
    require(receipt.get('returncode') == 0 and not receipt.get('changed_inputs')
            and receipt.get('namespace_coverage') is True
            and receipt.get('integrity_error') is None, 'Incomplete measurement receipt')
    provenance = json.loads((folder / 'inputs-before.json').read_text())
    require(provenance['source'] == source and provenance['case_set'] == 'measure',
            'Wrong measured source or case set')
    with (folder / 'namespaces.tsv').open() as stream:
        namespaces = list(csv.DictReader(stream, delimiter='\t'))
    packages = [Path(row['path']) for row in namespaces if row['name'] == 'dtatools']
    require(len(packages) == 1 and packages[0].is_absolute() and packages[0].name == 'dtatools',
            'Expected one recorded dtatools installation')
    package = packages[0]
    original_inputs = provenance['inputs']
    input_paths = [row['path'] for row in original_inputs]
    require(len(input_paths) == len(set(input_paths)), 'Duplicate measurement input')
    require(str(package / 'DESCRIPTION') in input_paths, 'Installed package was not bound')
    common = {row['path']: row for row in original_inputs
              if not Path(row['path']).is_relative_to(package)}
    launcher = LAUNCHERS[source]
    require(common.get(launcher['path']) == launcher, 'Unexpected orchestration Python binding')
    del common[launcher['path']]
    require(all(str(path) in common for path in REQUIRED_COMMON), 'Missing expected driver or corpus input')
    command = provenance['command']
    require(len(command) == 3 and command[1:] == ['--vanilla', str(ROOT / 'measure-v4.R')]
            and command[0] in common, 'Unexpected measurement command')

    audit, _ = load_completed(audit_name, inputs, inventories)
    audit_inputs = json.loads((audit / 'inputs.json').read_text())['inputs']
    bindings = {item['path']: item for item in audit_inputs}
    for path in [folder / 'manifest.json', ROOT / (name + '-receipt.json')]:
        require(bindings.get(str(path)) == identity(path), 'Audit covers another run')
    audited = json.loads((audit / 'result.json').read_text())
    require(audited['returncode'] == 0 and audited['error'] is None
            and not audited['changed_inputs'] and audited['measurements'] == 50,
            'Failed raw-sample audit')
    with (folder / 'grid.csv').open() as stream:
        grid = list(csv.DictReader(stream))
    with (folder / 'measurements.csv').open() as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames == SCHEMA, 'Unexpected measurement metric schema')
        rows = list(reader)
    grid_keys = [tuple(row[key] for key in KEYS) for row in grid]
    require(len(grid_keys) == 25 and len(set(grid_keys)) == 25, 'Unexpected grid')
    indexed = {}
    for row in rows:
        key = tuple(row[field] for field in KEYS) + (row['mode'],)
        require(key not in indexed, 'Duplicate measurement')
        require(int(row['iterations']) == 7, 'Unexpected sample count')
        for field, value in row.items():
            if field.endswith('_bytes') or field == 'median_ms':
                require(math.isfinite(float(value)) and float(value) >= 0,
                        'Invalid metric: ' + field)
        require(float(row['median_ms']) > 0, 'Cannot compare zero duration')
        require(int(row['actual_input_columns']) == int(row['columns'])
                + (row['kind'] in ('grouped', 'by')), 'Wrong input width')
        indexed[key] = row
    require(set(indexed) == {key + (mode,) for key in grid_keys for mode in MODES},
            'Incomplete paired modes')
    return grid, indexed, common, command


def write_csv(path, rows):
    require(bool(rows), 'No comparison rows')
    with path.open('x', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    require(len(sys.argv) == 6,
            'Expected baseline run, baseline audit, candidate run, candidate audit, fresh output')
    baseline_name, baseline_audit, candidate_name, candidate_audit, output_name = sys.argv[1:]
    for name in sys.argv[1:]:
        require(Path(name).name == name and name not in ('', '.', '..'), 'Use direct-child names')
    output = ROOT / output_name
    require(not output.exists() and not output.is_symlink(), 'Output must be fresh')
    inputs = [identity(Path(__file__).resolve()), identity(Path(sys.executable).resolve())]
    inventories = {}
    baseline_grid, baseline, baseline_common, baseline_command = load_matrix(baseline_name, baseline_audit, BASELINE, inputs, inventories)
    candidate_grid, candidate, candidate_common, candidate_command = load_matrix(candidate_name, candidate_audit, CANDIDATE, inputs, inventories)
    require(baseline_grid == candidate_grid, 'Different measured grids')
    require(baseline_command == candidate_command and baseline_common == candidate_common,
            'Different driver, corpus, helper or common runtime bindings')
    output.mkdir()
    write(output / 'inputs.json', dict(inputs=inputs, inventories=inventories,
        baseline_source=BASELINE, candidate_source=CANDIDATE,
        common_measurement_inputs=baseline_common, measurement_command=baseline_command,
        orchestration_launchers=LAUNCHERS,
        scope='Completed products, receipts and raw-sample audits. The historical measurement runtime '
              'closure is not requalified by this arithmetic comparison. Python executable is bound; '
              'full Python modules and OS closure are not frozen.'))
    status = 'failed'
    failure = None
    tables = []
    flags = []
    try:
        for grid in baseline_grid:
            key = tuple(grid[field] for field in KEYS)
            pairings = [
                ('candidate_direct_vs_baseline_direct', baseline[key + ('direct',)], candidate[key + ('direct',)]),
                ('candidate_reference_vs_baseline_reference', baseline[key + ('safe_reference',)], candidate[key + ('safe_reference',)]),
                ('candidate_direct_vs_candidate_reference', candidate[key + ('safe_reference',)], candidate[key + ('direct',)]),
                ('baseline_direct_vs_baseline_reference', baseline[key + ('safe_reference',)], baseline[key + ('direct',)]),
            ]
            for comparison, reference, measured in pairings:
                ref_ms = float(reference['median_ms'])
                measured_ms = float(measured['median_ms'])
                delta = measured_ms - ref_ms
                ratio = measured_ms / ref_ms
                flag = delta > 1 and ratio > 1.1
                row = dict(grid, comparison=comparison, reference_ms=ref_ms,
                    measured_ms=measured_ms, delta_ms=delta, time_ratio=ratio,
                    investigate_time_regression=flag)
                for field in reference:
                    if field.endswith('_bytes'):
                        row['reference_' + field] = float(reference[field])
                        row['measured_' + field] = float(measured[field])
                        row['delta_' + field] = float(measured[field]) - float(reference[field])
                tables.append(row)
                if flag:
                    flags.append({field: row[field] for field in [*KEYS, 'comparison',
                        'reference_ms', 'measured_ms', 'delta_ms', 'time_ratio']})
        write_csv(output / 'comparisons.csv', tables)
        write(output / 'assessment.json', dict(status='requires_assessment',
            grid_cases=25, comparisons=len(tables), flags=flags,
            threshold='Investigate median increase strictly above 10% and 1 ms.',
            orchestration_difference='The baseline and candidate used the same pinned Python3.14.7 launcher. '
                'Both execute the same byte-identical measure-v4.py and exact Rscript --vanilla command. '
                'Python setup/integrity work occurs outside the timed R operations. All common R, '
                'dependency, expression driver, corpus and helper bindings match exactly. '
                'This comparison does not permit the different-launcher exception used for historical source57309.',
            interpretation='Direct names public dispatch; the baseline still delegates. '
                'The safe reference removes the redundant old retyping pass only for this checked corpus. '
                'Grouped/rowwise fixtures omit dataset labels because the candidate intentionally fixes '
                'their loss. R allocation and native counters overlap and must not be added. '
                'These tables do not measure write cost, retained memory or peak RSS. '
                'A flag is a diagnosis trigger, not proof of a repeatable regression.'))
        status = 'complete'
    except BaseException as error:
        failure = dict(type=type(error).__name__, message=str(error))
        raise
    finally:
        changed = changes(inputs)
        for folder, before in inventories.items():
            try:
                after = sorted(str(path) for path in Path(folder).iterdir())
            except (OSError, RuntimeError) as error:
                changed.append(dict(folder=folder, inventory_error=str(error)))
            else:
                if after != before:
                    changed.append(dict(folder=folder, inventory_changed=True))
        if changed:
            status = 'failed'
        write(output / 'result.json', dict(status=status, failure=failure, changed_inputs=changed,
            comparisons=len(tables), utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
        products = [identity(path) for path in sorted(output.iterdir())]
        write(output / 'manifest.json', dict(products=products, excluded_self='manifest.json',
                                            excluded_receipt='completed-receipt.json'))
        write(output / 'completed-receipt.json', dict(status=status,
            manifest=identity(output / 'manifest.json'), changed_inputs=changed))
    require(status == 'complete', 'Comparison failed; inspect retained records')
    print(json.dumps(dict(comparisons=len(tables), flags=len(flags), output=str(output))))


if __name__ == '__main__':
    main()

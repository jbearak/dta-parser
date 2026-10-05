#!/usr/bin/env python3
"""A two-pair setup-inclusive LUT screen with preinstalled, separately bound DLLs."""
import argparse
import csv
import datetime
import hashlib
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
CASES = (
    ('byte', 'float', 'low', 262143), ('byte', 'float', 'low', 262144),
    ('byte', 'float', 'full_observed', 1000000), ('byte', 'double', 'full_observed', 1000000),
    ('int', 'float', 'low', 262143), ('int', 'float', 'low', 262144),
    ('int', 'float', 'low', 1000000), ('int', 'float', 'full_observed', 1000000),
    ('int', 'double', 'full_observed', 262144), ('int', 'double', 'full_observed', 1000000))
REPRESENTATIONS = ('compact', 'typed_double', 'ordinary')
STABLE = ('input_sha256', 'input_missing', 'input_zeros', 'observed_codes', 'result_sha256',
          'missing_sha256', 'result_missing', 'result_storage', 'mutation_checked', 'cleared_sha256')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def binding(library):
    package = library.resolve() / 'dtatools'
    dlls = [p for p in (package / 'libs').rglob('*') if p.is_file() and p.suffix in ('.so', '.dll', '.dylib')]
    require(len(dlls) == 1, 'Expected one installed native DLL')
    files = [dlls[0], package / 'DESCRIPTION', package / 'NAMESPACE',
             package / 'R/dtatools.rdb', package / 'R/dtatools.rdx']
    require(all(p.is_file() for p in files), 'Incomplete installed package')
    return {str(p.relative_to(package)): sha(p) for p in files}


def summarize(output, qualify):
    measurements, stable = {}, {}
    for number in (1, 2):
        for variant in ('baseline', 'candidate'):
            path = output / f'{variant}-round{number}.csv'
            with path.open(newline='') as stream:
                rows = list(csv.DictReader(stream))
            require(len(rows) == 30, 'Expected thirty rows in ' + str(path))
            seen, orders = set(), {}
            for row in rows:
                case = (row['width'], row['destination'], row['cardinality'], int(row['n']))
                representation = row['representation']
                key = case + (representation,)
                require(case in CASES and representation in REPRESENTATIONS and key not in seen,
                        'Unexpected or duplicate case in ' + str(path))
                seen.add(key)
                require(int(row['case']) == CASES.index(case) + 1 and int(row['round']) == number,
                        'Case or round order changed')
                orders.setdefault(case, []).append(int(row['order']))
                reps = int(row['iterations'])
                require(reps > 0 and int(row['native_calls']) == (0 if representation == 'ordinary' else reps),
                        'Native route was not qualified')
                require(row['mutation_checked'] == ('FALSE' if representation == 'ordinary' else 'TRUE'),
                        'Mutation qualification changed')
                for prefix in ('', 'numerator_'):
                    for state in ('compact', 'materialized'):
                        require(row[prefix + state + '_before'] == row[prefix + state + '_after'],
                                'Operand state changed')
                require(row['compact_before'] == ('TRUE' if representation == 'compact' else 'FALSE') and
                        row['materialized_before'] == 'FALSE', 'Unexpected input state')
                facts = tuple(row[k] for k in STABLE)
                require(key not in stable or stable[key] == facts, 'Fixture or qualified output changed')
                stable[key] = facts
                if not qualify:
                    cpu = float(row['cpu']) / reps
                    require(math.isfinite(cpu) and cpu > 0, 'Invalid CPU measurement')
                    measurements[(variant, number) + key] = cpu
            require(all(sorted(v) == [1, 2, 3] for v in orders.values()), 'Incomplete representation orders')
    if qualify:
        return {'qualified_cases': 120, 'timings_taken': False}
    median = statistics.median
    result = []
    for case in CASES:
        def times(variant, representation):
            return [measurements[(variant, number) + case + (representation,)] for number in (1, 2)]
        old, new = times('baseline', 'compact'), times('candidate', 'compact')
        typed, ordinary = times('candidate', 'typed_double'), times('candidate', 'ordinary')
        result.append(dict(zip(('width', 'destination', 'cardinality', 'n'), case),
            baseline_ms=median(old) * 1000, candidate_ms=median(new) * 1000,
            paired_gain=median(a / b for a, b in zip(old, new)),
            paired_gains=[a / b for a, b in zip(old, new)],
            compact_typed=median(a / b for a, b in zip(new, typed)),
            compact_ordinary=median(a / b for a, b in zip(new, ordinary)),
            typed_drift=median(a / b for a, b in zip(times('baseline', 'typed_double'), typed))))
    return {'scope': 'Two paired fresh-process screening rounds only; per-call table setup and allocation included. '
                     'Public constructor-accepted codes, sparse missing tags and zero denominators. '
                     'No universal performance claim or threshold tuning beyond these cases.',
            'observations': 120, 'cases': result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--baseline-library', type=Path,
                        default=Path('/private/tmp/dta-compact-float-facts-evidence/candidate-library-v1'))
    parser.add_argument('--candidate-library', type=Path,
                        default=Path('/private/tmp/dta-integer-reciprocal-lookup-evidence/candidate-library-v1'))
    parser.add_argument('--qualify-only', action='store_true')
    args = parser.parse_args()
    executable = shutil.which('Rscript')
    require(executable is not None, 'Rscript is required')
    worker = HERE / 'lookup-worker.R'
    libraries = {'baseline': args.baseline_library.resolve(), 'candidate': args.candidate_library.resolve()}
    require(libraries['baseline'] != libraries['candidate'], 'Separate installed libraries are required')
    before = {name: binding(path) for name, path in libraries.items()}
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    receipt = {'started': now(), 'worker_sha256': sha(worker), 'controller_sha256': sha(Path(__file__)),
               'libraries': {name: str(path) for name, path in libraries.items()}, 'library_before': before,
               'qualify_only': args.qualify_only, 'commands': [],
               'protocol': 'Four sequential fresh-R workers in AB/BA order; ten cases, three representations; '
                           'rotated representation orders; CPU-based calibration to approximately 100 ms per observation; '
                           'every public reciprocal call includes any per-call LUT setup; all qualification outside clocks.'}
    for number in (1, 2):
        for variant in (('baseline', 'candidate') if number == 1 else ('candidate', 'baseline')):
            command = [executable, '--vanilla', str(worker), str(libraries[variant]), str(number),
                       str(output / f'{variant}-round{number}.csv'), variant,
                       'qualify' if args.qualify_only else 'timed']
            started = now()
            run = subprocess.run(command, text=True, capture_output=True)
            receipt['commands'].append({'variant': variant, 'round': number, 'command': command,
                'started': started, 'ended': now(), 'exit_code': run.returncode,
                'stdout': run.stdout, 'stderr': run.stderr})
            write(output / 'receipt.json', receipt)
            require(run.returncode == 0, 'Worker failed; see receipt.json')
            print(variant, 'round', number, run.stdout.strip(), flush=True)
    receipt['library_after'] = {name: binding(path) for name, path in libraries.items()}
    require(receipt['library_after'] == before, 'Installed library changed')
    require(sha(worker) == receipt['worker_sha256'] and sha(Path(__file__)) == receipt['controller_sha256'],
            'Worker or controller changed')
    write(output / 'summary.json', summarize(output, args.qualify_only))
    receipt.update({'ended': now(), 'exit_code': 0, 'observations': 120})
    write(output / 'receipt.json', receipt)


if __name__ == '__main__':
    main()

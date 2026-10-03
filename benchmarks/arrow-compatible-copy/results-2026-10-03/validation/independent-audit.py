"""Independent completed-run audit. Do not execute during a timing window."""
import csv
import hashlib
import importlib.util
import itertools
import json
import math
import statistics
from collections import Counter
from pathlib import Path

ROOT = Path('<compatible-copy-evidence>')
RUN = ROOT / 'paired-v1'
QUAL = ROOT / 'qualification-v2'
FIXTURES = ROOT / 'fixtures-v3'
REPO = Path('<compatible-copy-checkout>')
OUT = Path('<independent-audit>/compatible-copy-audit.json')
BUILDS = {
    'baseline': Path('<baseline-integration-evidence>/combined-build'),
    'candidate': ROOT / 'candidate-v1',
}
COMMITS = {'baseline': '9e6977a426f56b50044bf6d62c108c2d1e3548ed',
           'candidate': '9ee3916ca078cb46f49f932b7cbb3ded70a6a99f'}
TARGETS = ('payload_f64', 'semantic_f64', 'integer_i32')
CONTROLS = ('nullable_f64', 'nullable_i32', 'widen_f32', 'compact_i16')
IDS = TARGETS + CONTROLS
KEYS = ('id', 'threads', 'mode')
CASES = set(itertools.product(IDS, ('1', '16'), ('read', 'full')))
HASHES = ('values_sha256', 'metadata_sha256', 'types_sha256', 'consumption_sha256', 'state_sha256')
TIMES = ('read_cpu_seconds', 'read_wall_seconds', 'consume_cpu_seconds',
         'consume_wall_seconds', 'total_cpu_seconds', 'total_wall_seconds', 'gc_cpu_seconds')
ROUTES = {'payload_f64': 'PayloadDouble', 'semantic_f64': 'SemanticDouble',
          'integer_i32': 'Integer', 'nullable_f64': 'SemanticDouble',
          'nullable_i32': 'Integer', 'widen_f32': 'SemanticDouble', 'compact_i16': 'ProfiledCompact'}
TYPES = {'payload_f64': 'double', 'semantic_f64': 'double', 'integer_i32': 'int32',
         'nullable_f64': 'double', 'nullable_i32': 'int32', 'widen_f32': 'float', 'compact_i16': 'int16'}


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def close(actual, expected, message):
    require(math.isclose(float(actual), expected, rel_tol=1e-12, abs_tol=1e-13), message)


def schedule(number):
    targets = tuple(itertools.permutations(TARGETS))[number - 1]
    controls = CONTROLS if number % 2 else tuple(reversed(CONTROLS))
    ids = targets + controls if number % 2 else controls + targets
    threads = ('1', '16') if number % 2 else ('16', '1')
    modes = ('read', 'full') if number % 2 else ('full', 'read')
    return list(itertools.product(ids, threads, modes))


def observations(directory, rounds, phase):
    raw = read(directory / 'raw.csv')
    rebuilt = []
    names = set()
    for number in range(1, rounds + 1):
        for ordinal, case in enumerate(schedule(number), 1):
            for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
                name = f'{number:02}-{ordinal:02}-{variant}-' + '-'.join(case) + '.csv'
                names.add(name)
                batch = read(directory / name)
                require(len(batch) == 1, 'worker row count')
                row = batch[0]
                require(tuple(row[k] for k in KEYS) == case and row['phase'] == phase, 'worker identity')
                rebuilt.append(dict(round=str(number), ordinal=str(ordinal), variant=variant, **row))
    require(raw == rebuilt, 'all worker/raw values and execution order')
    require({p.name for p in directory.glob('*.csv')} - {'raw.csv', 'summary.csv'} == names,
            'exact worker CSV inventory')
    require(len(raw) == 56 * rounds, 'complete row count')
    for row in raw:
        require(row['rows'] == '2000000' and row['columns'] == '8', 'dimensions')
        compact = row['id'] == 'compact_i16'
        require(row['retained'] == str(compact).upper(), 'retained flag')
        require(int(row['compact_columns']) == int(row['retained_columns']) == (8 if compact else 0),
                'actual compact/native retained columns')
        require(int(row['chunks_per_column']) == (31 if compact else 0), 'native chunk count')
        require(row['profile'] == str(row['id'] != 'semantic_f64').upper() and
                row['route'] == ROUTES[row['id']], 'profile/declared route')
        expected_na = 28 if row['id'] in TARGETS[:2] else 32 if row['id'] in (
            'nullable_f64', 'nullable_i32', 'compact_i16') else 0
        require(int(row['expected_na_per_column']) == expected_na, 'expected full missing count')
        require(all(len(row[k]) == 64 and set(row[k]) <= set('0123456789abcdef') for k in HASHES),
                'full semantic/state hash formats')
        values = {k: float(row[k]) for k in TIMES}
        require(all(math.isfinite(v) and v >= 0 for v in values.values()), 'finite intervals')
        if phase == 'qualify':
            require(all(v == 0 for v in values.values()), 'no-clock qualification')
        else:
            require(values['read_cpu_seconds'] > 0 and values['read_wall_seconds'] > 0, 'read intervals')
            for unit in ('cpu', 'wall'):
                consumed = values[f'consume_{unit}_seconds']
                require(consumed > 0 if row['mode'] == 'full' else consumed == 0, 'consumption interval')
                close(values[f'total_{unit}_seconds'], values[f'read_{unit}_seconds'] + consumed,
                      'read plus consumption equals workflow')
            require(values['gc_cpu_seconds'] <= values['total_cpu_seconds'] + .01, 'GC bounds')
    for fixture in IDS:
        require(len({tuple(r[k] for k in HASHES) for r in raw if r['id'] == fixture}) == 1,
                'semantic/ownership identity across builds/threads/workflows/rounds')
    for number in range(1, rounds + 1):
        for variant in BUILDS:
            selected = [r for r in raw if r['round'] == str(number) and r['variant'] == variant]
            require(Counter(tuple(r[k] for k in KEYS) for r in selected) == Counter({k: 1 for k in CASES}),
                    'each build/round matrix')
    if phase == 'measure':
        for case in CASES:
            require(Counter(('baseline' if number % 2 else 'candidate') for number in range(1, 7)) ==
                    Counter(baseline=3, candidate=3), 'paired build balance')
        require(Counter(tuple(c[0] for c in schedule(n) if c[0] in TARGETS)[::4] for n in range(1, 7)) ==
                Counter(itertools.permutations(TARGETS)), 'six target permutations')
    return raw


rows = observations(RUN, 6, 'measure')
qualified = observations(QUAL, 1, 'qualify')
for row in qualified:
    matches = [r for r in rows if tuple(r[k] for k in KEYS) == tuple(row[k] for k in KEYS)]
    require(all(tuple(r[k] for k in HASHES) == tuple(row[k] for k in HASHES) for r in matches),
            'qualified full signatures match every timed observation')
summary = read(RUN / 'summary.csv')
require(Counter(tuple(r[k] for k in KEYS) for r in summary) == Counter({k: 1 for k in CASES}), 'summary matrix')
for item in summary:
    key = tuple(item[k] for k in KEYS)
    groups = {v: sorted([r for r in rows if r['variant'] == v and tuple(r[k] for k in KEYS) == key],
                        key=lambda r: int(r['round'])) for v in BUILDS}
    for variant, selected in groups.items():
        for metric in TIMES:
            values = [float(r[metric]) for r in selected]
            for label, function in (('median', statistics.median), ('min', min), ('max', max)):
                close(item[f'{variant}_{label}_{metric}'], function(values), 'every median/minimum/maximum')
    for metric in ('read_cpu_seconds', 'read_wall_seconds', 'total_cpu_seconds', 'total_wall_seconds'):
        close(item[metric + '_speedup'], statistics.median(float(r[metric]) for r in groups['baseline']) /
              statistics.median(float(r[metric]) for r in groups['candidate']), 'median ratio')
        paired = [float(b[metric]) / float(c[metric]) for b, c in zip(groups['baseline'], groups['candidate'])]
        for label, function in (('median', statistics.median), ('min', min), ('max', max)):
            close(item[f'paired_{label}_{metric}_speedup'], function(paired), 'paired ratios')

binding = json.loads((RUN / 'binding-before.json').read_text())
require(binding == json.loads((RUN / 'binding-after.json').read_text()), 'full before/after binding')
require(binding == json.loads((QUAL / 'binding-before.json').read_text()) ==
        json.loads((QUAL / 'binding-after.json').read_text()), 'identically bound qualification')
for directory, count, phase in ((RUN, 336, 'measure'), (QUAL, 56, 'qualify')):
    completion = json.loads((directory / 'completion.json').read_text())
    require(completion['phase'] == phase and completion['observations'] == count and
            completion['full_results_exact'] and completion['bindings_unchanged'] and
            completion['timings_collected'] == (phase == 'measure'), 'successful completion')
    for name, digest in completion['artifacts'].items():
        require(sha(directory / name) == digest, 'completion artifact ' + name)
for name, digest in binding['controllers'].items():
    require(sha(Path(name)) == digest, 'current controller/helper ' + name)
current_fixtures = {p.name: sha(p) for p in sorted(FIXTURES.iterdir()) if p.is_file()}
require(current_fixtures == binding['fixtures'], 'current complete fixture/oracle/facts inventory')
recorder = REPO / 'benchmarks/r-file-readers/record-builds.py'
spec = importlib.util.spec_from_file_location('compatible_build_records', recorder)
records = importlib.util.module_from_spec(spec)
spec.loader.exec_module(records)
for role, path in BUILDS.items():
    actual_variant = json.loads((path / 'build-receipt.json').read_text())['variant']
    receipt, patch, receipt_hash = records.verified_receipt(path, actual_variant)
    require(dict(receipt=receipt, receipt_sha256=receipt_hash) == binding['builds'][role],
            'current complete source/installed/compiler/DLL binding ' + role)
    require(not patch and receipt['base_commit'] == COMMITS[role], 'exact clean measured source')
    require(receipt['toolchain']['R_runtime_sha256'] == binding['runtime']['R_runtime_sha256'],
            'actual worker/build runtime equality')
require(sha(Path(binding['runtime']['launcher'])) == binding['runtime']['launcher_sha256'],
        'current exact worker launcher')

manifest = read(FIXTURES / 'fixtures.csv')
physical = read(FIXTURES / 'physical-batches.csv')
schemas = json.loads((FIXTURES / 'schema-facts.json').read_text())
require(Counter(r['id'] for r in manifest) == Counter({k: 1 for k in IDS}), 'fixture matrix')
require(len(physical) == 7 * 31 * 8 and set(schemas) == set(IDS), 'physical/schema matrix')
for fixture in IDS:
    selected = [r for r in physical if r['id'] == fixture]
    require(Counter((int(r['batch']), r['column']) for r in selected) ==
            Counter({(batch, 'x' + str(column)): 1 for batch in range(1, 32) for column in range(1, 9)}),
            'every actual batch/column')
    schema = schemas[fixture]
    require(len(schema['fields']) == 8 and all(f['type'] == TYPES[fixture] for f in schema['fields']),
            'actual physical schema types')
    for row in selected:
        require(row['type'] == TYPES[fixture] and
                int(row['rows']) == (65536 if int(row['batch']) < 31 else 33920), 'batch type/length')
        nulls = int(row['nulls'])
        require(nulls > 0 if fixture in ('nullable_f64', 'nullable_i32') else nulls == 0,
                'per-batch nullable/compatible admission fact')
    for column in range(1, 9):
        same = [r for r in selected if r['column'] == 'x' + str(column)]
        require(sum(int(r['rows']) for r in same) == 2000000, 'full physical row count')
        require(sum(int(r['nulls']) for r in same) == (32 if fixture in ('nullable_f64', 'nullable_i32') else 0),
                'complete Arrow validity null count')

report = dict(result='PASS', observations=len(rows), qualified_observations=len(qualified), summary_rows=len(summary),
    checks=['all worker/raw identities and complete balanced matrix', 'all medians/minima/maxima and paired ratios',
            'complete value/metadata/consumption/native-state hashes', 'actual schema/batch/null facts',
            'all completion artifacts and exact before/after/qualification bindings',
            'current full fixtures/oracles and current complete clean source/compiler/installed/DLL inventories',
            'exact worker launcher and recorded build/runtime equality'],
    speedups=[{k: row[k] for k in KEYS + ('read_cpu_seconds_speedup', 'read_wall_seconds_speedup',
        'total_cpu_seconds_speedup', 'total_wall_seconds_speedup', 'paired_median_read_cpu_seconds_speedup',
        'paired_median_total_cpu_seconds_speedup')} for row in summary],
    intervals={metric: [min(float(r[metric]) for r in rows), max(float(r[metric]) for r in rows)] for metric in TIMES},
    caveats=['Individual first-read intervals retain their clock-resolution limit.',
             'Physical schema/validity facts support eligibility; this audit does not add runtime dispatch counters.',
             'Profile FALSE also disables checksums; build comparisons are within each fixed route.',
             'Consumption includes sum and a full is.na vector, not every possible downstream operation.',
             'One desktop host with uncontrolled filesystem cache; no universal reader, RSS or ingestion zero-copy claim.'],
    artifacts={name: sha(RUN / name) for name in ('raw.csv', 'summary.csv', 'binding-before.json',
               'binding-after.json', 'protocol.json', 'source.patch', 'completion.json')})
OUT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
print(json.dumps({k: report[k] for k in ('result', 'observations', 'qualified_observations', 'summary_rows', 'speedups', 'intervals')}, indent=2))

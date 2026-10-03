"""Independent artifact audit. Execute only after the exclusive run finishes."""
import csv
import hashlib
import importlib.util
import itertools
import json
import math
import shutil
import statistics
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path('<work>')
P = ROOT / 'acceptance-v1'
D = ROOT / 'acceptance-controller'
OUT = ROOT / 'acceptance-independent-audit.json'
FIELDS = ('width', 'missing', 'operation', 'representation')
REPS = ('compact', 'typed_double', 'ordinary')
SCALAR = ('scale_binary', 'scale_general', 'pair_compact_double', 'add_scalar',
          'subtract_scalar', 'reverse_subtract', 'reverse_divide')
OPERATIONS = {'int': SCALAR + ('mixed_add', 'mixed_multiply'),
              'float': SCALAR, 'long': ('long_float_add',)}
CASES = [(width, missing, operation) for width in ('int', 'float', 'long')
         for missing in ('FALSE', 'TRUE') for operation in OPERATIONS[width]]
EXPECTED = {case + (rep,) for case in CASES for rep in REPS}
IDENTITY = ('result_sha256', 'missing_sha256', 'missing_count', 'result_storage',
            'input_sha256', 'y_sha256', 'mutation_checked', 'cleared_sha256', 'compact_before', 'materialized_before',
            'y_compact_before', 'y_materialized_before', 'ywidth')
BUILDS = {'baseline': Path('<baseline-build>'),
          'candidate': ROOT / 'candidate-final'}
RECEIPT_VARIANTS = {'baseline': 'baseline', 'candidate': 'baseline'}
QUALIFICATIONS = {'baseline': ROOT / 'acceptance-baseline-qualification.csv',
                  'candidate': ROOT / 'acceptance-candidate-qualification.csv'}
COMMITS = {'baseline': '7003eba901671797ee91fffc97f08e28a1f7f515',
           'candidate': '3a02e6d13309441366a7a727fdc934f424ce66c6'}


def need(ok, label):
    if not ok:
        raise RuntimeError(label)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return list(csv.DictReader(path.open(newline='')))


def close(value, target, label):
    need(math.isclose(float(value), target, rel_tol=1e-12, abs_tol=1e-14), label)


def validate_batch(batch, number, phase):
    need(Counter(tuple(row[k] for k in FIELDS) for row in batch) ==
         Counter({key: 1 for key in EXPECTED}), 'unique 102-case matrix')
    wanted = []
    for case_number, case in enumerate(CASES, 1):
        order = [REPS[(j + number + case_number - 1) % 3] for j in (1, 2, 3)]
        if number % 2 == 0:
            order.reverse()
        wanted.extend((case + (rep,), case_number, position)
                      for position, rep in enumerate(order, 1))
    need([(tuple(row[k] for k in FIELDS), int(row['case']), int(row['order']))
          for row in batch] == wanted, 'exact case and representation order')
    missing_x = set(range(13, 1000001, 997))
    missing_y = set(range(19, 1000001, 991))
    # The source subtracts 5000 after reducing 13*i modulo 10001.
    zero_start = (5000 * pow(13, -1, 10001)) % 10001
    zero_x = set(range(zero_start, 1000001, 10001))
    for row in batch:
        need(int(row['round']) == number and int(row['n']) == 1000000, 'round/rows')
        repetitions = int(row['iterations'])
        need(repetitions > 0, 'positive iterations')
        if phase == 'qualify':
            need(repetitions == 1 and row['cpu'] == row['wall'] == 'NA', 'no-clock qualification')
        else:
            need(all(math.isfinite(float(row[k])) and float(row[k]) > 0
                     for k in ('cpu', 'wall')), 'positive finite intervals')
        need(float(row['native_calls']) == (0 if row['representation'] == 'ordinary' else repetitions),
             'native route in both builds')
        for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
            need(row[prefix + '_before'] == row[prefix + '_after'], 'source state unchanged')
        compact = row['representation'] == 'compact'
        typed = row['representation'] != 'ordinary'
        need(row['mutation_checked'] == str(typed).upper(), 'typed missing count checked by mutation')
        cleared = row['cleared_sha256']
        need((len(cleared) == 64 and set(cleared) <= set('0123456789abcdef'))
             if typed else cleared == '', 'full cleared-result hash')
        mixed = row['operation'] in ('mixed_add', 'mixed_multiply', 'long_float_add')
        need(row['compact_before'] == str(compact).upper() and row['materialized_before'] == 'FALSE',
             'source representation admission')
        need(row['ywidth'] == ('float' if mixed else 'double'), 'right operand width')
        need(row['y_compact_before'] == str(compact and mixed).upper() and
             row['y_materialized_before'] == 'FALSE', 'right operand representation')
        for key in ('result_sha256', 'missing_sha256', 'input_sha256', 'y_sha256'):
            need(len(row[key]) == 64 and set(row[key]) <= set('0123456789abcdef'), 'full hash format')
        expected_missing = missing_x.copy() if row['missing'] == 'TRUE' else set()
        if row['missing'] == 'TRUE' and (mixed or row['operation'] == 'pair_compact_double'):
            expected_missing |= missing_y
        if row['operation'] == 'reverse_divide' and row['representation'] != 'ordinary':
            expected_missing |= zero_x
        need(int(row['missing_count']) == len(expected_missing), 'independent missing-position count')


completion = json.loads((P / 'completion.json').read_text())
need(completion['observations'] == 1224 and completion['rounds'] == 6 and
     all(completion[key] is True for key in ('exact_results', 'missing_cache_matches',
         'source_state_unchanged', 'provenance_unchanged', 'worker_runtime_unchanged', 'typed_missing_mutation_checked')), 'completion')
qualification_completion = json.loads((ROOT / 'acceptance-qualification-completion.json').read_text())
need(qualification_completion['status'] == 'PASS' and qualification_completion['total'] == 204 and
     qualification_completion['cases_per_build'] == 102 and
     all(qualification_completion[k] is True for k in ('exact_results_and_missing_caches',
          'native_routes_checked_in_both_builds', 'provenance_unchanged', 'source_state_unchanged')),
     '204-case qualification receipt')
qualification_files = {str(ROOT / f'acceptance-{role}-qualification.{ext}')
                       for role in ('baseline', 'candidate') for ext in ('csv', 'log')}
qualification_files |= {str(ROOT / f'acceptance-qualification-{phase}.json') for phase in ('before', 'after')}
need(set(qualification_completion['input_sha256']) == qualification_files, 'exact qualification input set')
for name, digest in qualification_completion['input_sha256'].items():
    need(sha(Path(name)) == digest, 'prior qualification artifact binding')
need((ROOT / 'acceptance-qualification-before.json').read_bytes() ==
     (ROOT / 'acceptance-qualification-after.json').read_bytes(), 'qualification inventories unchanged')
rows = read(P / 'raw.csv')
need(len(rows) == 1224, 'complete observation count')
rebuilt = []
worker_files = []
for number in range(1, 7):
    for role in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
        path = P / f'{number:02}-{role}.csv'
        batch = read(path)
        validate_batch(batch, number, 'measure')
        rebuilt.extend(dict(variant=role, **row) for row in batch)
        worker_files.append(path)
need(rebuilt == rows, 'exact worker/raw identity and paired build order')
need(set(P.glob('*.csv')) == set(worker_files) | {P / 'raw.csv', P / 'summary.csv'}, 'worker file set')
groups = defaultdict(list)
for row in rows:
    groups[tuple(row[k] for k in FIELDS)].append(row)
for key, batch in groups.items():
    need(len(batch) == 12 and len({tuple(row[k] for k in IDENTITY) for row in batch}) == 1,
         'stable full semantics across builds/rounds')
for role in BUILDS:
    for case in CASES:
        orders = []
        for number in range(1, 7):
            batch = sorted([row for row in rows if row['variant'] == role and
                int(row['round']) == number and tuple(row[k] for k in FIELDS[:-1]) == case],
                key=lambda row: int(row['order']))
            orders.append(tuple(row['representation'] for row in batch))
        need(Counter(orders) == Counter(itertools.permutations(REPS)), 'all six representation orders')
for case in CASES:
    need(len({(row['input_sha256'], row['y_sha256']) for row in rows if
              tuple(row[k] for k in FIELDS[:-1]) == case}) == 1, 'same full inputs across representations')

summary = read(P / 'summary.csv')
need(Counter((row['variant'], *(row[k] for k in FIELDS[:-1])) for row in summary) ==
     Counter({(role, *case): 1 for role in BUILDS for case in CASES}), 'complete 68-row summary')
extra_summaries = []
for case in CASES:
    values = {(role, rep, metric): {int(row['round']): float(row[metric]) / int(row['iterations'])
              for row in groups[case + (rep,)] if row['variant'] == role}
              for role in BUILDS for rep in REPS for metric in ('cpu', 'wall')}
    for s in [row for row in summary if tuple(row[k] for k in FIELDS[:-1]) == case]:
        role = s['variant']
        med = {rep: statistics.median(values[role, rep, 'cpu'].values()) for rep in REPS}
        for rep in REPS:
            close(s[rep], med[rep], 'CPU median')
        close(s['compact_typed_ratio'], med['compact'] / med['typed_double'], 'typed CPU ratio')
        close(s['compact_ordinary_ratio'], med['compact'] / med['ordinary'], 'ordinary CPU ratio')
        close(s['paired_compact_typed_ratio'], statistics.median(
            values[role, 'compact', 'cpu'][n] / values[role, 'typed_double', 'cpu'][n]
            for n in range(1, 7)), 'paired compact/typed CPU ratio')
        close(s['compact_speedup'], statistics.median(values['baseline', 'compact', 'cpu'].values()) /
              statistics.median(values['candidate', 'compact', 'cpu'].values()), 'compact CPU speedup')
    extra = dict(zip(FIELDS[:-1], case))
    for rep in REPS:
        for metric in ('cpu', 'wall'):
            for role in BUILDS:
                extra[f'{role}_{rep}_{metric}'] = statistics.median(values[role, rep, metric].values())
            extra[f'{rep}_{metric}_speedup'] = extra[f'baseline_{rep}_{metric}'] / extra[f'candidate_{rep}_{metric}']
            extra[f'{rep}_{metric}_paired_speedup'] = statistics.median(
                values['baseline', rep, metric][n] / values['candidate', rep, metric][n]
                for n in range(1, 7))
    extra_summaries.append(extra)

before = json.loads((P / 'provenance-before.json').read_text())
after = json.loads((P / 'provenance-after.json').read_text())
need(all(before[k] == after[k] for k in ('builds', 'controllers', 'runtime')), 'before/after binding')
need(completion['source_patch_sha256'] == sha(P / 'source.patch'), 'source patch binding')
protocol = json.loads((P / 'protocol.json').read_text())
need(protocol['rounds'] == 6 and protocol['rows'] == 1000000 and protocol['cases_per_build_round'] == 102,
     'protocol geometry')
paths = {name: D / name for name in ('general-run.py', 'general-worker.R')}
paths['run.py'] = Path('<private-work>/dta-native-integration-final-20261003/benchmarks/native-operations/run.py')
need(set(paths) == set(before['controllers']), 'exact controller set')
for name, digest in before['controllers'].items():
    need(sha(paths[name]) == digest, 'current controller ' + name)
spec = importlib.util.spec_from_file_location('independent_integer_reciprocal_records', paths['run.py'])
records = importlib.util.module_from_spec(spec)
spec.loader.exec_module(records)
for role, build in BUILDS.items():
    saved = before['builds'][role]
    need(saved['receipt']['base_commit'] == COMMITS[role] == protocol[role + '_commit'], 'exact source commit')
    need(saved['receipt']['variant'] == RECEIPT_VARIANTS[role], 'historical receipt variant differs from comparison role')
    need((build / 'source.patch').read_bytes() == b'', 'clean source build')
    need(records.inventory(build, saved['receipt']['variant']) == saved, 'current complete source/installed/DLL inventory')
    need(saved['receipt']['toolchain']['R_runtime_sha256'] == before['runtime']['R_runtime_sha256'], 'worker/build runtime')
    qualified = read(QUALIFICATIONS[role])
    validate_batch(qualified, 1, 'qualify')
    for row in qualified:
        key = tuple(row[k] for k in FIELDS)
        need(tuple(row[k] for k in IDENTITY) == tuple(groups[key][0][k] for k in IDENTITY), 'untimed qualification identity')
launcher = Path(shutil.which('Rscript')).resolve(strict=True)
need(sha(launcher) == before['runtime']['Rscript_launcher_sha256'], 'exact current Rscript')
home = Path(subprocess.check_output([str(launcher), '--vanilla', '-e', 'cat(R.home())'], text=True).strip())
need(sha(home / 'bin/exec/R') == before['runtime']['R_runtime_sha256'], 'exact current R runtime')
need(before['R'] == before['runtime']['R_version'], 'descriptive R version')
version = subprocess.check_output([str(launcher), '--vanilla', '-e', 'cat(R.version.string)'], text=True).strip()
need(version == before['runtime']['R_version'], 'exact current R descriptive version')
report = dict(result='PASS', observations=len(rows), summary_rows=len(summary), qualification_observations=204,
    source_commits=COMMITS, receipt_variants=RECEIPT_VARIANTS, summary=extra_summaries,
    interval_cpu_range=[min(float(row['cpu']) for row in rows), max(float(row['cpu']) for row in rows)],
    interval_wall_range=[min(float(row['wall']) for row in rows), max(float(row['wall']) for row in rows)],
    checks=['Independent complete 102-case matrix and exact case/build/representation order',
            'Worker/raw identity and all six representation permutations',
            'Full result/storage/source/missing hashes, independent missing counts, and native route in both builds',
            'Every reported CPU median/control ratio and additional wall/paired ratios',
            'Both untimed 102-case qualification identities',
            'Current exact source/installed/DLL inventories and recorded build-time compiler identity',
            'Current exact launcher/R runtime and controller hashes'],
    caveats=['One host and constructed deterministic columns; typed results impose policy beyond bare arithmetic.',
             'The retained interval target is not the minimum observed interval.',
             'Package-test and source-archive conformance evidence is separately bound; this performance audit does not rerun those checks.'],
    artifacts={path.name: sha(path) for path in [*worker_files, *(P / name for name in
        ('raw.csv', 'summary.csv', 'protocol.json', 'provenance-before.json', 'provenance-after.json',
         'completion.json', 'source.patch'))]})
OUT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
print(json.dumps(dict(result='PASS', observations=len(rows), summary_rows=len(summary), output=str(OUT))))

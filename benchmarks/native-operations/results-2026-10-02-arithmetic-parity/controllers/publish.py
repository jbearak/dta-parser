#!/usr/bin/env python3
"""Publish the complete arithmetic acceptance run, never a partial run.

Usage from the repository root: publish.py RESULTS CANDIDATE_BUILD
This script performs publication only when invoked. Diagnostic experiments
remain explicitly separate from the source-bound final acceptance results.
"""
from pathlib import Path
import csv
import hashlib
import importlib.util
import json
import math
import re
import statistics
import subprocess
import sys

repo = Path.cwd().resolve()
work = Path('<work>')
previous_work = Path('<previous-work>')
if len(sys.argv) != 3:
    raise SystemExit('usage: publish.py RESULTS CANDIDATE_BUILD')
results, candidate = (Path(value).resolve() for value in sys.argv[1:])
out = repo / 'benchmarks/native-operations/results-2026-10-02-arithmetic-parity'
baseline_commit = '0a9c7090c100d68d4fa3005d707049e1b3d9c9a9'
source_map, pending = [], {}
replacements = [
    (str(repo), '<repo>'), (str(work), '<work>'),
    (str(previous_work), '<previous-work>'),
    ('<reader-work>', '<reader-work>'),
    ('<runtime-source-work>', '<runtime-source-work>'),
    ('<user>', '<user>'),
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_json(path):
    return json.loads(path.read_text())


def csv_rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def sanitize(raw, artifact):
    text = raw.decode()
    for old, new in replacements:
        text = text.replace(old, new)
    text = re.sub(r'/(?:private/)?var/folders/[^\s"\'<>]+', '<temporary>', text)
    # These exact illustrative paths are already public in the controller
    # README. Preserve that document's source hash; do not exempt arbitrary
    # temporary paths or a longer private path sharing one of these prefixes.
    privacy_scan = text
    for example in ('/private/tmp/native-ops-baseline',
                    '/private/tmp/native-ops-candidate',
                    '/private/tmp/native-ops-results',
                    '/private/tmp/reader-inputs'):
        privacy_scan = re.sub(re.escape(example) + r'(?=[\s"\'`]|$)',
                              '<public-example>', privacy_scan)
    require(not re.search(r'/(?:Users|home|private/tmp|tmp)/', privacy_scan),
            'Unmapped private path in publication artifact: ' + artifact)
    return text.encode()


def queue(src, relative, expected_sha256=None):
    require(src.is_file() and not src.is_symlink(), 'Missing/nonordinary artifact: ' + str(src))
    raw = src.read_bytes()
    require(len(raw) <= 2_000_000, 'Unexpectedly large publication artifact: ' + relative)
    if expected_sha256 is not None:
        require(sha(raw) == expected_sha256, 'Artifact changed: ' + str(src))
    data = sanitize(raw, relative)
    require(relative not in pending, 'Duplicate publication destination: ' + relative)
    pending[relative] = data
    source_map.append({
        'artifact': relative, 'source_sha256': sha(raw),
        'published_sha256': sha(data),
        'transformation': 'private path substitution' if raw != data else 'none',
    })


def generated(relative, value):
    require(relative not in pending, 'Duplicate generated artifact: ' + relative)
    pending[relative] = sanitize(value, relative)


# Check every prerequisite before creating the public directory.
require(not out.exists(), 'Publication directory already exists')
completion = read_json(results / 'completion.json')
protocol = read_json(results / 'protocol.json')
before = read_json(results / 'provenance-before.json')
after = read_json(results / 'provenance-after.json')
require(protocol['rounds'] == 6 and completion['observations'] == 864,
        'Publication requires six paired rounds and exactly 864 observations')
require(protocol['operations'] == ['multiply', 'divide', 'add'],
        'Publication requires the arithmetic-only protocol')
require(completion['exact_results'] is True and completion['provenance_unchanged'] is True,
        'Benchmark completion checks did not pass')
require(protocol['baseline_commit'] == baseline_commit,
        'Measured baseline is not the intended accepted merge commit')
for key in ('builds', 'fixtures', 'controllers'):
    require(before[key] == after[key], 'Timing provenance changed: ' + key)
require(sha((results / 'source.patch').read_bytes()) == completion['source_patch_sha256'],
        'Benchmark source patch changed after completion')

controller_root = repo / 'benchmarks/native-operations'
for filename in ('run.py', 'worker.R'):
    require(sha((controller_root / filename).read_bytes()) == before['controllers'][filename],
            'Current timing controller differs: ' + filename)
spec = importlib.util.spec_from_file_location('publication_native_operations', controller_root / 'run.py')
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)
expected_cases = {case for case in controller.EXPECTED_CASES
                  if case[2] in ('multiply', 'divide', 'add')}
require(len(expected_cases) == 72, 'Arithmetic matrix must contain exactly 72 cases')
builds = {'baseline': work / 'acceptance-baseline', 'candidate': candidate}
for name, build in builds.items():
    binding = before['builds'][name]
    # This rechecks recorded compiler inputs, source trees, private input
    # record, DLL equality, and recorder versions, rather than trusting a
    # receipt merely because it exists beside the installed library.
    require(controller.inventory(build, name) == binding,
            'Supplied build changed or differs from timed build: ' + name)
    receipt = binding['receipt']
    require(receipt['base_commit'] == protocol[name + '_commit'],
            'Build identity differs from protocol: ' + name)
    require(not (build / 'source.patch').read_text().strip(),
            'Committed-source publication cannot omit a source overlay')
    for filename, digest in {
        'build-receipt.json': binding['receipt_sha256'],
        'input-record.json': receipt['input_record_sha256'],
        'source.patch': receipt['source_patch_sha256'],
        'build.log': receipt['build_log_sha256'],
    }.items():
        queue(build / filename, f'builds/{name}/{filename}', digest)

candidate_receipt = before['builds']['candidate']['receipt']
for name, digest in candidate_receipt['source_inventory'].items():
    require(sha((repo / 'r-package/dtatools' / name).read_bytes()) == digest,
            'Current package source differs from measured candidate: ' + name)
require(subprocess.run(['git', 'diff', '--quiet', protocol['candidate_commit'], '--',
                        'r-package/dtatools'], check=False).returncode == 0,
        'Current package differs from the measured commit')

observations = []
for round_number in range(1, 7):
    for name in builds:
        stem = f'{round_number:02}-{name}'
        require((results / (stem + '.log')).is_file(), 'Missing worker log: ' + stem)
        rows = csv_rows(results / (stem + '.csv'))
        controller.validate_round(rows, round_number, expected_cases)
        require(len(rows) == 72, 'Worker result is not exactly 72 observations: ' + stem)
        observations.extend(dict(variant=name, **row) for row in rows)
        for extension in ('.csv', '.log'):
            queue(results / (stem + extension), 'timings/' + stem + extension)
raw = csv_rows(results / 'raw.csv')
row_key = lambda row: (int(row['round']), row['variant'], row['format'],
                       row['width'], row['operation'], row['representation'])
require(len(raw) == 864 and sorted(observations, key=row_key) == sorted(raw, key=row_key),
        'Combined observations differ from the twelve worker outputs')
groups = {}
for row in observations:
    case = '-'.join(row[key] for key in ('format', 'width', 'operation'))
    groups.setdefault((case, row['representation']), []).append(row)
    if row['variant'] == 'candidate' and row['representation'] in ('compact', 'typed_double'):
        require(int(float(row['native_scalar_calls'])) == int(row['iterations']),
                'Timed candidate did not enter the native arithmetic kernel')
for key, rows in groups.items():
    require(len({(row['result_sha256'], row['full_result_sha256'], row['result_storage'])
                 for row in rows}) == 1, 'Result or storage differs: ' + str(key))
summary = csv_rows(results / 'summary.csv')
require(len(summary) == 72 and len({(r['case'], r['representation']) for r in summary}) == 72,
        'Final summary is not the complete unique case matrix')
for row in summary:
    selected = groups[(row['case'], row['representation'])]
    values = {}
    for variant in builds:
        for metric, field in (('cpu', 'cpu_seconds'), ('wall', 'elapsed_seconds')):
            name = variant + '_' + metric
            values[name] = statistics.median(float(r[field]) / int(r['iterations'])
                                             for r in selected if r['variant'] == variant)
            require(math.isclose(float(row[name]), values[name], rel_tol=1e-12, abs_tol=1e-15),
                    'Summary differs from raw observations: ' + name)
    require(math.isclose(float(row['cpu_speedup']),
                         values['baseline_cpu'] / values['candidate_cpu'], rel_tol=1e-12),
            'Summary speedup differs from raw observations')
for filename in ('completion.json', 'protocol.json', 'provenance-before.json',
                 'provenance-after.json', 'source.patch', 'raw.csv', 'summary.csv'):
    queue(results / filename, 'timings/' + filename)

for filename in ('run.py', 'worker.R', 'README.md', 'test-run.py'):
    queue(controller_root / filename, 'controllers/' + filename,
          before['controllers'].get(filename))
build_controllers = {
    'builder': repo / 'benchmarks/r-file-readers/build-snapshot.py',
    'recorder': repo / 'benchmarks/r-file-readers/record-builds.py',
    'existing_recorder_helpers': repo / 'benchmarks/io-optimization/record-builds.py',
}
for name, path in build_controllers.items():
    queue(path, 'controllers/build/' + name + '.py', candidate_receipt['artifact_sha256'][name])

validation_path = work / 'validation-source-bindings.json'
validation = read_json(validation_path)
require(validation['benchmark_commit'] == protocol['candidate_commit'] and
        validation['benchmark_receipt_sha256'] == before['builds']['candidate']['receipt_sha256'] and
        validation['package_source_inventory'] == candidate_receipt['source_inventory'] and
        validation['full_suite_source_differences'] == [],
        'Validation is not bound to the measured candidate sources and receipt')
required_validation = {'acceptance-full-tests.csv', 'acceptance-full-tests.log',
                       'acceptance-conformance.log', 'test-native-run-final.log',
                       'check-full-tests.R'}
require(required_validation <= set(validation['validation_artifacts']),
        'Validation binding omits required acceptance artifacts')
for filename, digest in validation['validation_artifacts'].items():
    require(Path(filename).name == filename and filename not in ('', '.', '..'),
            'Validation artifact must be a direct work-directory filename')
    require((work / filename).stat().st_size > 0, 'Empty validation artifact: ' + filename)
    queue(work / filename, 'validation/' + filename, digest)
tests = csv_rows(work / 'acceptance-full-tests.csv')
require(tests and sum(int(row['passed']) for row in tests) > 0,
        'Full-suite validation contains no passing assertions')
require(all(float(row['failed']) == 0 and row['error'] in ('FALSE', 'False', '0') for row in tests),
        'Full-suite validation contains failures or errors')
queue(validation_path, 'validation/validation-source-bindings.json')

# The original diagnostic must also pass against the clean acceptance DLL.
# Its small, fixed case complements rather than replaces the paired matrix.
accepted_repro = work / 'acceptance-repro'
accepted_text = (accepted_repro / 'result.dput').read_text()
accepted_dll = re.search(r'(?<![\w])dll_sha256 = "([a-f0-9]{64})"', accepted_text)
require(accepted_dll is not None and accepted_dll.group(1) ==
        candidate_receipt['installed_inventory']['libs/dtatools.so'],
        'Acceptance reproduction did not run the measured clean candidate DLL')
for marker in ('passed = TRUE', 'values_equal = TRUE',
               'native_route_verified = TRUE', 'compact_unmaterialized = TRUE'):
    require(marker in accepted_text, 'Acceptance reproduction lacks success proof: ' + marker)
accepted_rows = csv_rows(accepted_repro / 'observations.csv')
require(len(accepted_rows) == 6 and
        {(int(row['round']), row['representation']) for row in accepted_rows} ==
        {(round_number, representation) for round_number in range(1, 4)
         for representation in ('compact', 'typed_double')},
        'Acceptance reproduction is missing complete paired observations')
for row in accepted_rows:
    require(int(row['iterations']) > 0 and int(row['native_calls']) == int(row['iterations']),
            'Acceptance reproduction did not use the native route for every call')
    require(row['result_storage'] == ('long' if row['representation'] == 'compact' else 'double'),
            'Acceptance reproduction used an unexpected output storage')
    if row['representation'] == 'compact':
        require(row['compact_before'] == row['compact_after'] == 'TRUE' and
                row['materialized_before'] == row['materialized_after'] == 'FALSE',
                'Acceptance reproduction materialized its compact input')
require(len({row['result_sha256'] for row in accepted_rows}) == 1,
        'Acceptance reproduction result hashes differ')
accepted_medians = {representation: statistics.median(
    float(row['cpu_seconds']) / int(row['iterations']) for row in accepted_rows
    if row['representation'] == representation) for representation in ('compact', 'typed_double')}
require(accepted_medians['compact'] / accepted_medians['typed_double'] <= 1.10,
        'Acceptance reproduction did not meet its diagnostic parity gate')
require('PARITY PASS' in (work / 'acceptance-repro.log').read_text(),
        'Acceptance reproduction log does not report completion')
for filename in ('observations.csv', 'result.dput'):
    queue(accepted_repro / filename, 'validation/acceptance-repro/' + filename)
queue(work / 'acceptance-repro.log', 'validation/acceptance-repro/run.log')
generated('validation/acceptance-repro/binding.json', json_bytes({
    'benchmark_commit': protocol['candidate_commit'],
    'benchmark_receipt_sha256': before['builds']['candidate']['receipt_sha256'],
    'dll_sha256': accepted_dll.group(1),
    'controller_sha256': sha((work / 'repro.R').read_bytes()),
    'diagnostic_limit': 1.10,
    'compact_over_typed_double': accepted_medians['compact'] / accepted_medians['typed_double'],
    'artifacts': {name: sha(path.read_bytes()) for name, path in {
        'observations.csv': accepted_repro / 'observations.csv',
        'result.dput': accepted_repro / 'result.dput',
        'run.log': work / 'acceptance-repro.log',
    }.items()},
}))

# Historical red/green evidence demonstrates the diagnostic, not acceptance.
# Keep its own build identities; neither experiment is relabelled as the final
# candidate or as the six-round comparison.
red_dir = work / 'run-20261002T184219-40960'
green_dir = work / 'combined-v1-repro'
red_receipt_path = previous_work / 'final-candidate-v2/build-receipt.json'
red_receipt = read_json(red_receipt_path)
green_record_path = work / 'combined-v1/record.json'
green_record = read_json(green_record_path)
v5_record_path = work / 'combined-v5/record.json'
v5_record = read_json(v5_record_path)
diagnostic_record = {
    'purpose': 'Historical red/green diagnosis; not final acceptance evidence.',
    'limits': 'Three paired sweeps of one qualified int * 2 case; the 1.10 ratio is a diagnostic gate, not a CI promise.',
    'script_sha256': sha((work / 'repro.R').read_bytes()),
    'red_build_receipt_sha256': sha(red_receipt_path.read_bytes()),
    'green_build_record_sha256': sha(green_record_path.read_bytes()),
    'v5_build_record_sha256': sha(v5_record_path.read_bytes()),
    'files': {},
}
for label, directory, log, dll in (
    ('red', red_dir, work / 'initial-red.log', red_receipt['installed_inventory']['libs/dtatools.so']),
    ('green', green_dir, work / 'combined-v1-repro.log', green_record['dll_sha256']),
    ('v5', work / 'combined-v5-repro', work / 'combined-v5-repro.log', v5_record['dtatools.so_sha256']),
):
    text = (directory / 'result.dput').read_text()
    require(re.search(r'(?<![\w])dll_sha256 = "([a-f0-9]{64})"', text).group(1) == dll,
            'Historical diagnostic result is not bound to its own build: ' + label)
    require(('passed = FALSE' if label == 'red' else 'passed = TRUE') in text,
            'Historical red/green diagnostic status differs: ' + label)
    require(len(csv_rows(directory / 'observations.csv')) == 6,
            'Historical diagnostic is missing paired observations: ' + label)
    for src, filename in ((directory / 'observations.csv', 'observations.csv'),
                          (directory / 'result.dput', 'result.dput'), (log, 'run.log')):
        relative = f'diagnostics/repro/{label}/{filename}'
        queue(src, relative)
        diagnostic_record['files'][relative] = sha(src.read_bytes())
queue(work / 'repro.R', 'diagnostics/repro/repro.R')
queue(red_receipt_path, 'diagnostics/repro/red/build-receipt.json')
queue(green_record_path, 'diagnostics/repro/green/build-record.json')
generated('diagnostics/repro/record.json', json_bytes(diagnostic_record))

# Compiler evidence is from the final source kernels, but its instrumented
# compiler outputs are not substituted for the clean acceptance build.
v5 = work / 'combined-v5'
require(v5_record['evidence_compile_returncode'] == 0,
        'Compiler evidence build failed')
for filename, digest in v5_record['source_hashes'].items():
    require(candidate_receipt['source_inventory']['src/' + filename] == digest and
            sha((v5 / 'src' / filename).read_bytes()) == digest,
            'Compiler evidence source differs from final candidate: ' + filename)
require(sha((v5 / 'src/numeric-payload.s').read_bytes()) ==
        v5_record['evidence_numeric-payload.s_sha256'], 'Compiler assembly evidence changed')
for filename in ('record.json', 'codegen.log', 'scale-remarks.txt', 'float-loop-excerpts.txt'):
    queue(v5 / filename, 'compiler/' + filename)
classifier = v5 / 'classifier-check'
classifier_record = read_json(classifier / 'record.json')
require(classifier_record['compile_returncode'] == classifier_record['run_returncode'] == 0,
        'Float classifier differential check failed')
require(classifier_record['new_header_sha256'] ==
        candidate_receipt['source_inventory']['src/numeric-arithmetic-scale.h'],
        'Float classifier check does not match final candidate source')
for key in ('old_header', 'new_header'):
    require(sha(Path(classifier_record[key]).read_bytes()) == classifier_record[key + '_sha256'],
            'Float classifier comparison header changed: ' + key)
queue(classifier / 'record.json', 'compiler/classifier-check/record.json')
queue(classifier / 'classifier-check.c', 'compiler/classifier-check/classifier-check.c',
      classifier_record['generated_source_sha256'])
queue(classifier / 'compile.log', 'compiler/classifier-check/compile.log')
queue(classifier / 'result.log', 'compiler/classifier-check/result.log',
      classifier_record['result_sha256'])

allocation = work / 'allocation-probe'
allocation_record = read_json(allocation / 'record.json')
queue(allocation / 'record.json', 'diagnostics/allocation/record.json')
for filename, digest in allocation_record['files'].items():
    require(sha((allocation / filename).read_bytes()) == digest,
            'Allocation diagnostic changed: ' + filename)
    if filename.endswith(('.so', '.o', '.dylib', '.dll')):
        continue
    queue(allocation / filename, 'diagnostics/allocation/' + filename, digest)
require(sha(Path(allocation_record['source_evidence']['path']).read_bytes()) ==
        allocation_record['source_evidence']['sha256'], 'Exact R allocator source changed')
queue(work / 'forced-long/record.json', 'diagnostics/allocation/forced-long-build-record.json')
finalizer_record = read_json(allocation / 'finalizer-record.json')
queue(allocation / 'finalizer-record.json', 'diagnostics/allocation/finalizer-record.json')
for filename, digest in finalizer_record['files'].items():
    require(sha((allocation / filename).read_bytes()) == digest,
            'Finalizer diagnostic changed: ' + filename)
    if not filename.startswith('r-source/'):
        queue(allocation / filename, 'diagnostics/allocation/' + filename, digest)
queue(work / 'finalizer-checkpoint/record.json',
      'diagnostics/allocation/finalizer-checkpoint-build-record.json')
generated('diagnostics/README.txt', (
    'These are historical diagnosis artifacts, separate from final acceptance.\n'
    'The forced-long build is deliberately invalid outside its qualified int * 2 fixture.\n'
    'The exact-window finalizer checkpoint simulates immediate-finalizer/event callback behavior;\n'
    'the default-Rscript scan did not reproduce the corruption.\n'
    'Private binaries, object files, full R source copies, and installed libraries are omitted.\n'
    'Records retain their original hashes; the allocator record identifies the exact upstream R archive.\n'
    'publication-source-map.json binds every copied artifact before/after path substitution.\n'
).encode())

patch = subprocess.check_output(['git', 'diff', '--no-ext-diff', baseline_commit,
                                 protocol['candidate_commit'], '--', 'r-package/dtatools'])
generated('candidate-git.patch', patch)
queue(Path(__file__).resolve(), 'controllers/publish.py')
generated('publication-source-map.json', json_bytes(source_map))
generated('publication-manifest.json', json_bytes({name: sha(data) for name, data in sorted(pending.items())}))
out.mkdir()
for relative, data in pending.items():
    destination = out / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
print(out)

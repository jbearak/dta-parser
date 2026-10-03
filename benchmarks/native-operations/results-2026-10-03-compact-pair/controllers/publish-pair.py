#!/usr/bin/env python3
"""Publish final compact-pair acceptance plus separately labelled diagnostics.

Run from the repository root: publish-pair.py PRIVATE_WORK NEW_PUBLIC_DIRECTORY
Original evidence remains byte-identical; the source map records each published
private-path substitution. Installed binaries and complete disassemblies are not
published. This is an artifact packager, not an independent numerical audit.
"""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

work, output = [Path(value).resolve() for value in sys.argv[1:]]
repo = Path.cwd().resolve()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


require(not output.exists(), 'Output already exists')
timings = work / 'acceptance-timings'
before, after = [load(timings / ('provenance-' + side + '.json')) for side in ('before', 'after')]
completion = load(timings / 'completion.json')
require(completion['observations'] == 1224 and completion['rounds'] == 6 and
        completion['exact_results'] and completion['provenance_unchanged'] and
        completion['worker_runtime_unchanged'], 'Final acceptance is incomplete')
require(all(before[key] == after[key] for key in ('builds', 'controllers', 'runtime')),
        'Final provenance changed')
controller = work / 'acceptance-controller/general-run.py'
spec = importlib.util.spec_from_file_location('pair_acceptance', controller)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for path in [controller, controller.with_name('general-worker.R'), module.RECORDS_PATH]:
    require(sha(path.read_bytes()) == before['controllers'][path.name], 'Measured controller changed')
for role in ('baseline', 'candidate'):
    require(module.RECORDS.inventory(work / ('acceptance-' + role), role) == before['builds'][role],
            'Measured build no longer verifies')
rows = list(csv.DictReader((timings / 'raw.csv').open()))
for role in ('baseline', 'candidate'):
    for round_number in range(1, 7):
        module.validate_round([row for row in rows if row['variant'] == role and
                               int(row['round']) == round_number], round_number, role)
integration = load(work / 'integration-binding.json')
require(integration['status'] == 'PASS' and integration['source_equals_clean_build'] and
        integration['measured_candidate'] == before['builds']['candidate']['receipt']['base_commit'],
        'Separate main integration is not qualified')
require(subprocess.run(['git', 'diff', '--quiet', integration['source_commit'],
                        '--', 'r-package/dtatools']).returncode == 0,
        'Package source differs from qualified integration')
require(module.RECORDS.inventory(work / 'integration-candidate', 'candidate') ==
        integration['integration_build'], 'Integrated build no longer verifies')
validation = load(work / 'acceptance-validation-binding.json')
require(validation['status'] == 'PASS' and validation['current_source_equals_candidate'] and
        validation['builds'] == before['builds'], 'Qualification does not bind the final builds')
require('R package conformance: PASS' in (work / 'acceptance-conformance.log').read_text(),
        'Required conformance did not pass')
pending, mapping = {}, []
replacements = [(str(work), '<work>'), (str(repo), '<repo>'),
                ('<independent-audit-work>', '<independent-audit-work>'),
                ('<prior-arithmetic-work>', '<prior-arithmetic-work>'),
                (str(Path.home()), '<user>')]


def queue(source, relative):
    raw = source.read_bytes()
    text = raw.decode()
    for old, new in replacements:
        text = text.replace(old, new)
    text = re.sub(r'/(?:private/)?var/folders/[^\s"\'<>]+', '<temporary>', text)
    require(not re.search(r'/(?:Users|home|private/tmp|tmp)/', text), 'Unmapped path in ' + relative)
    data = text.encode()
    require(relative not in pending, 'Duplicate publication artifact')
    pending[relative] = data
    mapping.append(dict(artifact=relative, source_sha256=sha(raw), published_sha256=sha(data),
                        transformation='none' if raw == data else 'private path substitution'))


def directory(source, relative):
    for path in sorted(source.iterdir()):
        if path.is_file():
            queue(path, relative + '/' + path.name)


directory(timings, 'timings')
for role in ('baseline', 'candidate'):
    for name in ('build-receipt.json', 'input-record.json', 'source.patch', 'build.log'):
        queue(work / ('acceptance-' + role) / name, 'builds/' + role + '/' + name)
for name in ('general-run.py', 'general-worker.R', 'test-general-run.py'):
    queue(work / 'acceptance-controller' / name, 'controllers/' + name)
queue(module.RECORDS_PATH, 'controllers/run.py')
queue(Path(__file__).resolve(), 'controllers/publish-pair.py')
queue(work / 'bind-final-qualification.py', 'validation/bind-final-qualification.py')
queue(Path('<prior-arithmetic-work>/acceptance-v2-full-tests.R'), 'validation/full-tests.R')
for name in ('full-tests.csv', 'full-tests.log', 'conformance.log', 'baseline-qualification.csv',
             'baseline-qualification.log', 'candidate-qualification.csv', 'candidate-qualification.log',
             'controller-tests.log', 'controller-tests-optimized.log', 'native-manifest-tests.log',
             'validation-binding.json', 'timing-controller.log'):
    queue(work / ('acceptance-' + name), 'validation/' + name)
for name in ('build-receipt.json', 'input-record.json', 'source.patch', 'build.log'):
    queue(work / 'integration-candidate' / name, 'integration/build/' + name)
for name in ('integration-binding.json', 'bind-integration.py', 'integration-full-tests.csv',
             'integration-full-tests.log', 'integration-qualification.csv', 'integration-qualification.log',
             'integration-conformance.log', 'integration-conformance.json',
             'integration-conformance-gate.sh', 'validate-conformance-archive.py'):
    queue(work / name, 'integration/validation/' + name)
# Isolated stages remain separate experiments; their gains are not multiplied.
for stage, folder in [('pair-domain', 'pair-timings'), ('float-product', 'float-product-timings'),
                      ('float-add-sub', 'float-add-sub-timings')]:
    directory(work / folder, 'diagnostics/' + stage + '/timings')
for stage, folder in [('pair-domain', 'pair-diagnostic'), ('float-product', 'float-product-diagnostic'),
                      ('float-add-sub', 'float-add-sub-diagnostic')]:
    for name in ('general-run.py', 'general-worker.R', 'test-general-run.py'):
        queue(work / folder / name, 'diagnostics/' + stage + '/controllers/' + name)
for stage, folder in [('pair-domain', 'pair-prototype'), ('float-product', 'float-product-prototype'),
                      ('float-add-sub', 'float-add-sub-prototype')]:
    for name in ('build-receipt.json', 'input-record.json', 'source.patch'):
        queue(work / folder / name, 'diagnostics/' + stage + '/build/' + name)
for folder in ('f32-equivalence', 'f32-add-sub-equivalence'):
    for path in sorted((work / folder).iterdir()):
        if path.is_file() and path.suffix in ('.py', '.c', '.h', '.json', '.md', '.log') and path.name != 'proof-draft.md':
            queue(path, 'proofs/' + folder + '/' + path.name)
for name in ('float-product-stage.md', 'float-product-audit.py', 'float-product-audit.json',
             'float-add-sub-audit.py', 'float-add-sub-audit.json',
             'residual-pair-audit.py', 'residual-pair-audit.json',
             'mixed-add-control-audit.py', 'mixed-add-control-audit.json',
             'mixed-add-disassembly-binding.py', 'mixed-add-disassembly-binding.json',
             'pair-validation-binding.json', 'pair-compiler-diagnostic.json',
             'float-product-validation-binding.json', 'float-product-compiler-diagnostic.json',
             'float-add-sub-validation-binding.json', 'bind-float-add-sub-qualification.py',
             'float-add-sub-fadd-loop.txt', 'float-add-sub-fsub-loop.txt', 'float-add-sub-fmul-loop.txt'):
    queue(work / name, 'diagnostics/' + name)
pending['publication-source-map.json'] = json_bytes(mapping)
pending['publication-manifest.json'] = json_bytes({name: sha(data) for name, data in sorted(pending.items())})
output.mkdir(parents=True)
for name, data in pending.items():
    path = output / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
print('Published', len(pending), 'source-bound artifacts')

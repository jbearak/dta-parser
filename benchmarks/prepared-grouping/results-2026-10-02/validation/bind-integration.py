from pathlib import Path
import csv
import hashlib
import importlib.util
import json
import shutil
import subprocess

root = Path('<repo>')
work = Path('<development>')
build = Path('<integration>')
validation = work / 'final-validation'
spec = importlib.util.spec_from_file_location('grouping_run', root / 'benchmarks/prepared-grouping/run.py')
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

inventory = run.NATIVE.inventory(build, 'candidate')
receipt = inventory['receipt']
assert receipt['base_commit'] == '60b9b0c18e6007ec5115ff2eb519ff7a13fb61c8'
assert not (build / 'source.patch').read_text().strip()
assert all(sha(root / 'r-package/dtatools' / name) == digest
           for name, digest in receipt['source_inventory'].items())
focused = list(csv.DictReader((work / 'integration-focused.csv').open()))
assert len(focused) == 108 and sum(int(row['passed']) for row in focused) == 6070
assert all(row['failed'] == '0' and row['error'] == 'FALSE' and row['skipped'] == 'FALSE'
           and row['warning'] == '0' for row in focused)
measured = json.loads((validation / 'validation-binding.json').read_text())
assert receipt['source_inventory']['src/egen-groups.h'] == measured['candidate_package_sources']['src/egen-groups.h']
delta = subprocess.check_output(['git', 'diff', measured['candidate_commit'], receipt['base_commit'],
                                 '--', 'r-package/dtatools'], cwd=root)
renamed = {build / name: 'integration-' + name for name in
           ('build-receipt.json', 'input-record.json', 'build.log', 'source.patch')}
renamed.update({work / name: name for name in
                ('integration-focused.R', 'integration-focused.log', 'integration-focused.csv',
                 'bind-integration.py')})
for source, target in renamed.items():
    assert not (validation / target).exists()
    shutil.copy2(source, validation / target)
(validation / 'integration-source-delta.patch').write_bytes(delta)
binding = {
    'integration_commit': receipt['base_commit'],
    'main_commit': '895dd204d1e90b058461063ba37573214aeda0fa',
    'measured_commit': measured['candidate_commit'],
    'scope': 'Post-measurement clean integration validation only; timing evidence remains bound to the earlier measured package.',
    'grouping_implementation_unchanged': True,
    'grouping_source_sha256': receipt['source_inventory']['src/egen-groups.h'],
    'build_inventory': inventory,
    'tests': {'blocks': 108, 'assertions': 6070, 'failures': 0, 'errors': 0, 'skips': 0, 'warnings': 0},
    'artifacts': {name: sha(validation / name) for name in sorted(list(renamed.values()) + ['integration-source-delta.patch'])},
}
(validation / 'integration-binding.json').write_text(json.dumps(binding, indent=2, sort_keys=True) + '\n')
measured['artifacts'].update({name: sha(validation / name) for name in
                            list(renamed.values()) + ['integration-source-delta.patch', 'integration-binding.json']})
(validation / 'validation-binding.json').write_text(json.dumps(measured, indent=2, sort_keys=True) + '\n')
print('Bound 6070 integration assertions to', receipt['base_commit'])

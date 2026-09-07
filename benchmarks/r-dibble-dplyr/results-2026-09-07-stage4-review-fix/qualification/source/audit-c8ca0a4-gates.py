"""Independently recheck source, log, test-count and crate evidence without rerunning gates."""
from pathlib import Path
import csv
import hashlib
import json
import stat
import subprocess
import tarfile

ROOT = Path('/private/tmp/dta-direct-stage4-validation')
CHECKS = ROOT / 'checks-c8ca0a4'
WORKSPACE = ROOT / 'workspace-gates-c8ca0a4'
REPO = Path('/private/tmp/dta-direct-stage4')
SOURCE = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


gate = json.loads((CHECKS / 'exact-gates-manifest.json').read_text())
require(gate['source_sha'] == SOURCE, 'Wrong gate source')
require(digest(Path(gate['source_manifest'])) == gate['source_manifest_sha256'], 'Changed source manifest')
source = json.loads(Path(gate['source_manifest']).read_text())
require(digest(Path(source['archive'])) == source['archive_sha256'] == gate['archive_sha256'],
        'Changed source archive')
tree = subprocess.check_output(['git', 'ls-tree', '-rz', SOURCE], cwd=REPO)
objects = {}
for entry in tree.split(b'\0'):
    if entry:
        header, name = entry.split(b'\t', 1)
        mode, kind, blob = header.decode().split()
        require(kind == 'blob', 'Unexpected source object kind')
        objects[name.decode()] = (mode, blob)
require(set(objects) == set(source['entries']) == set(source['files']), 'Incomplete source inventory')
for name, record in source['entries'].items():
    path = Path(source['source_directory']) / name
    data = path.read_bytes()
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    require((record['git_mode'], record['git_blob']) == objects[name], f'Wrong Git source: {name}')
    require(blob == record['git_blob'] and digest(path) == record['sha256'] == source['files'][name],
            f'Changed source bytes: {name}')
    require(oct(stat.S_IMODE(path.stat().st_mode)) == record['mode'], f'Changed source mode: {name}')
for name, expected in gate['log_sha256'].items():
    require(digest(CHECKS / name) == expected, f'Changed gate log: {name}')
for name, expected in gate['driver_sha256'].items():
    require(digest(ROOT / name) == expected, f'Changed gate driver: {name}')
with (CHECKS / 'full-installed-loopback.csv').open() as stream:
    rows = list(csv.DictReader(stream))
totals = {key: sum(int(row[key]) if row[key] not in ('TRUE', 'FALSE') else int(row[key] == 'TRUE')
                   for row in rows) for key in ['failed', 'skipped', 'error', 'warning', 'passed']}
require(totals == {'failed': 0, 'skipped': 0, 'error': 0, 'warning': 4, 'passed': 16445},
        'Unexpected full-suite totals')
require('══ Skipped ' not in (CHECKS / 'haven-conformance-loopback.log').read_text(),
        'Haven coverage still skips a case')
workspace = json.loads((WORKSPACE / 'manifest.json').read_text())
initial = json.loads((WORKSPACE / 'initial-inputs.json').read_text())
require(initial['clean_status_including_ignored'] == '', 'Workspace not initially clean')
require(len(initial['workspace_inputs']) == len(objects), 'Incomplete workspace inputs')
for item in initial['workspace_inputs']:
    require((item['mode'], item['blob']) == objects[item['path']], 'Wrong workspace object')
    require(item['sha256'] == source['entries'][item['path']]['sha256'], 'Wrong workspace input bytes')
for name in ['initial-inputs', 'final-inputs'] + [f'{phase}-{side}' for phase in
        ['fmt', 'clippy', 'tests', 'doc', 'package'] for side in ['before', 'after']]:
    snapshot = json.loads((WORKSPACE / (name + '.json')).read_text())
    require(snapshot == initial, f'Workspace changed: {name}')
for command in workspace['commands']:
    require(command['exit_code'] == 0 and command['inputs_identical'], 'Failed workspace gate')
    require(digest(WORKSPACE / (command['name'] + '.log')) == command['log_sha256'],
            'Changed workspace gate log')
crate = json.loads((WORKSPACE / 'crate-identity.json').read_text())
require(digest(Path(crate['crate'])) == crate['sha256'], 'Changed verified crate')
with tarfile.open(crate['crate'], 'r:gz') as archive:
    members = {member.name: member for member in archive.getmembers() if member.isfile()}
    require(len(members) == crate['member_count'] == 27, 'Wrong crate member count')
    require(set(members) == {item['member'] for item in crate['members']}, 'Incomplete crate inventory')
    for item in crate['members']:
        member = members[item['member']]
        require(hashlib.sha256(archive.extractfile(member).read()).hexdigest() == item['sha256'] and
                member.size == item['bytes'] and oct(member.mode) == item['mode'], 'Changed crate member')
require(crate['vcs']['git']['sha1'] == SOURCE, 'Wrong crate VCS source')
require(crate['vcs']['git'].get('dirty', False) is False, 'Crate reports dirty source')
output = ROOT / 'root-c8ca0a4-gate-audit.json'
with output.open('x') as stream:
    json.dump({'source_sha': SOURCE, 'source_files_and_git_objects': len(objects),
               'source_archive_sha256': source['archive_sha256'],
               'gate_logs_rehashed': len(gate['log_sha256']), 'gate_drivers_rehashed': len(gate['driver_sha256']),
               'full_suite_test_blocks': len(rows), 'independent_full_suite_totals': totals,
               'workspace_snapshots': 12, 'workspace_gates': len(workspace['commands']),
               'crate_members_verified': 27, 'crate_sha256': crate['sha256'],
               'auditor_sha256': digest(Path(__file__)),
               'limit': 'Read-only source/artifact/result audit. No gate rerun or timing claim. '
                        'Four full-suite warnings and standard package-check three warnings/two notes remain disclosed.'},
              stream, indent=2)
    stream.write('\n')
print('Verified 1950 source Git blobs/modes, 29 gate logs, 16445 R passes, 12 complete workspace snapshots and 27 crate members.')

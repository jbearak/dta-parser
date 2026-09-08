"""Read-only completed export, archive and Rust log audit."""
from pathlib import Path
import csv
import hashlib
import json
import re
import subprocess
import tarfile

ROOT = Path('/private/tmp/dta-direct-stage5-validation/implementation')
REPO = Path('/private/tmp/dta-direct-stage5')
SOURCE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
def git(*args):
    return subprocess.check_output(['git','-C',str(REPO),*args])
def blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
expected = {}
for entry in git('ls-tree','-r','-z',SOURCE).split(b'\0'):
    if not entry: continue
    metadata, path = entry.split(b'\t',1)
    mode, kind, identity = metadata.decode().split()
    assert kind == 'blob'
    expected[path.decode()] = (mode,identity)

for name in ['full-combined-01','rust-combined-01']:
    folder = ROOT/name
    bound = json.loads((folder/'inputs-before.json').read_text())
    input_paths = {x['path'] for x in bound['inputs']}
    with tarfile.open(folder/'source.tar') as archive:
        files = [x for x in archive.getmembers() if x.isfile()]
        assert {x.name for x in files} == set(expected)
        for member in files:
            mode, identity = expected[member.name]
            data = archive.extractfile(member).read()
            assert blob(data) == identity
            assert bool(member.mode & 0o111) == (mode == '100755')
            path = folder/'source'/member.name
            assert path.read_bytes() == data and str(path) in input_paths
    assert '/Library/Developer/CommandLineTools/usr/bin/clang' in input_paths
    assert any('python' in x.lower() for x in input_paths)
    preflight = (folder/'preflight-identity.R').read_text()
    assert SOURCE in preflight
    assert str(ROOT/'candidate-combined-01/library/dtatools/libs/dtatools.so') in preflight

rust = ROOT/'rust-combined-01'
inputs = json.loads((rust/'inputs-before.json').read_text())['inputs']
paths = {x['path'] for x in inputs}
metadata = json.loads((rust/'cargo-metadata.json').read_text())
dependency_files = set()
for package in metadata['packages']:
    directory = Path(package['manifest_path']).parent
    if not directory.is_relative_to(rust/'source'):
        dependency_files.update(str(x) for x in directory.rglob('*') if x.is_file())
assert dependency_files <= paths
assert str(rust/'cargo-metadata.json') in paths
preparation = json.loads((rust/'cargo-metadata-command.json').read_text())
assert preparation['exit_code'] == 0
records = json.loads((rust/'execution-result.json').read_text())['records']
assert [x['label'] for x in records] == ['preflight','fmt','clippy','tests','docs','package']
assert all(x['exit_code'] == 0 for x in records)
assert records[-1]['command'] == ['cargo','package','-p','dta-tools','--locked','--allow-dirty']

test_log = (rust/'tests.log').read_text()
results = re.findall(r'test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out',test_log)
assert sum(int(x[0]) for x in results) == 278
assert all(all(int(value) == 0 for value in row[1:]) for row in results)
assert all('warning:' not in (rust/(name+'.log')).read_text() for name in ['fmt','clippy','tests','docs'])
warnings = re.findall(r'^warning: ignoring test `([^`]+)` as `tests/[^`]+` is not included in the published package$', (rust/'package.log').read_text(), re.M)
assert warnings == ['arrow','conformance','encoding','file','fuzz_smoke','legacy','metadata','observations','strl','value_labels','write']
assert (rust/'package.log').read_text().count('warning:') == 11
crate = rust/'source/target/package/dta-tools-0.7.1.crate'
with tarfile.open(crate) as archive:
    members = archive.getmembers()
    assert len(members) == 26 and all(x.isfile() for x in members)
    assert not any('vcs_info' in x.name or '/tests/' in x.name for x in members)
    for member in members:
        relative = member.name.removeprefix('dta-tools-0.7.1/')
        assert relative != member.name and '..' not in Path(relative).parts
        if relative in ['Cargo.toml','Cargo.lock']:
            continue
        source_name = 'Cargo.toml' if relative == 'Cargo.toml.orig' else relative
        source = rust/'source/r-package/dtatools/src/dta-tools'/source_name
        assert archive.extractfile(member).read() == source.read_bytes()

rows = list(csv.DictReader((ROOT/'full-combined-01/tests.csv').open()))
expected_tests = {
    'removed and re-added column generations retain values and expire':8,
    'native generation interrupts leave reference state unchanged':67,
    'POSIX interrupts reach an active native generation checkpoint':67,
    'generation interrupt controls disarm after validation errors':6,
}
for title,count in expected_tests.items():
    selected = [x for x in rows if x['test'] == title]
    assert len(selected) == 1 and int(selected[0]['passed']) == count
    assert selected[0]['failed']=='0' and selected[0]['skipped']=='FALSE' and selected[0]['error']=='FALSE' and selected[0]['warning']=='0'

report = dict(status='pass', source=SOURCE, full_git_export_files=len(expected),
              cargo_resolved_dependency_files=len(dependency_files), rust_tests_passed=278,
              crate_files=26, crate_sha256=hashlib.sha256(crate.read_bytes()).hexdigest(),
              package_warnings=warnings, integrated_public_and_interrupt_tests=expected_tests,
              limits='Cargo doc is a documentation build, not a separate doctest run. Cargo creates and verifies its crate within one command; no separate pre-consumption hash is claimed for that internal step. External OS/SDK/Python closures remain outside scope.')
with Path(__file__).with_suffix('.json').open('x') as stream:
    json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))

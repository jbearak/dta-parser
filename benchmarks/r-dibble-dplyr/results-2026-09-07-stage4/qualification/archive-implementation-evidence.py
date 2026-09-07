from pathlib import Path
import hashlib, json
v = Path('/private/tmp/dta-direct-stage4-validation')
root = Path('/private/tmp/dta-direct-stage4')
base = root / 'benchmarks/r-dibble-dplyr/results-2026-09-07-stage4'
entries = []
def copy(source, relative):
    source = Path(source)
    data = source.read_bytes()
    target = base / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as stream:
        stream.write(data)
    if target.read_bytes() != data:
        raise RuntimeError('Archive mismatch: ' + str(target))
    entries.append(dict(source=str(source), destination=relative,
                        bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
for revision in ['7d56080', '976cc40', 'e343b3b']:
    destination = 'qualification/' + revision + '/'
    checks = v / ('checks-' + revision)
    for source in sorted(checks.rglob('*')):
        if not source.is_file():
            continue
        relative = str(source.relative_to(checks))
        if relative.startswith(('binary/', 'binary-installed-library/')):
            continue
        if source.suffix not in ['.log', '.json', '.R'] and '/bin/' not in relative:
            continue
        copy(source, destination + 'checks/' + relative)
    native = v / ('native-' + revision)
    if native.exists():
        for source in sorted(native.rglob('*')):
            if source.is_file() and source.suffix in ['.log', '.json', '.md', '.csv', '.txt']:
                copy(source, destination + 'native/' + str(source.relative_to(native)))
    copy(v / ('source-' + revision + '-manifest.json'), destination + 'source-manifest.json')
    copy(v / ('run-native-' + revision + '.py'), destination + 'run-native.py')
    install = v / ('candidate-' + revision + '-install.log')
    if install.exists():
        copy(install, destination + 'archive-install.log')
for pattern in ['workspace-*-working-9.log', 'workspace-working-9.json',
                'bridge-*-working-8.log', 'bridge-working-8.json',
                'bridge-*-working-20-format-fixed.log', 'bridge-working-20-format-fixed.json']:
    for source in sorted(v.glob(pattern)):
        copy(source, 'qualification/reused-working-gates/' + source.name)
for pattern in ['storage-review-round*.md', 'api-review-round*.md']:
    for source in sorted(v.glob(pattern)):
        copy(source, 'qualification/reviews/' + source.name)
copy(v / 'archive-implementation-evidence.py', 'qualification/archive-implementation-evidence.py')
# Exact prototype source and controls, plus the explicitly superseded first run.
for source in sorted((v / 'accessor-prototype').iterdir()):
    if source.suffix in ['.c', '.R', '.log', '.csv']:
        copy(source, 'diagnosis/accessor-prototype/' + source.name)
prototype_binaries = {source.name: dict(bytes=source.stat().st_size,
    sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    for source in (v / 'accessor-prototype').iterdir() if source.suffix in ['.o', '.so']}
(base / 'diagnosis/accessor-prototype/binary-digests.json').write_text(json.dumps(prototype_binaries, indent=2) + '\n')
selected = [
 'working-17-stale-object-disclosure.json', 'working-install-17-record.log',
 'read-fixes-working-17-record.log', 'aggregate-working-17.log',
 'working-install-17-record-rebuilt.log', 'read-fixes-working-17-record-rebuilt.log',
 'atomic-accessor-diagnosis.R', 'accessor-working-16.log', 'accessor-working-16.csv',
 'accessor-working-17-rebuilt.log', 'accessor-working-17-rebuilt.csv',
 'aggregate-read-diagnosis.R', 'aggregate-working-17-rebuilt.log',
 'aggregate-working-18.log', 'aggregate-working-19.log', 'aggregate-working-20.log',
 'atomic-read-diagnosis-working.R', 'read-diagnosis-baseline.csv', 'read-diagnosis-baseline.log',
 'read-diagnosis-7d56080.csv', 'read-diagnosis-7d56080.log',
 'read-diagnosis-working-20.csv', 'read-diagnosis-working-20.log',
 'read-fixes-red.log', 'read-fixes-working-14.log', 'read-fixes-working-15-parity.log',
 'string-unknown-constructor-independent.R', 'string-unknown-constructor-independent-7d56080.R',
 'string-unknown-constructor-independent-7d56080.log', 'string-unknown-constructor-independent-working-14.log',
 'owned-string-writer-callback-reproduction.R', 'owned-string-writer-callback-reproduction-7d56080.log',
 'owned-string-writer-callback-reproduction-e343b3b.log',
 'unknown-string-constructor-reproduction.R', 'unknown-string-constructor-reproduction-7d56080.log',
 'unknown-string-constructor-reproduction-e343b3b.log',
 'full-working-20.log', 'read-fixes-working-20-arrow-storage.log',
 'native-976cc40-diagnostic.R', 'native-976cc40-diagnostic.log',
 'dictionary-replacement-diagnosis.R', 'dictionary-replacement-diagnosis-working.R',
 'dictionary-replacement-7d56080.Rprofmem', 'dictionary-replacement-7d56080.log',
 'dictionary-replacement-976cc40.Rprofmem', 'dictionary-replacement-976cc40.log',
 'dictionary-replacement-working-21.Rprofmem', 'dictionary-replacement-working-21.log',
 'working-21-function-identity.log', 'working-install-21b-dictionary-fallback.log',
 'dictionary-replacement-working-21b.Rprofmem', 'dictionary-replacement-working-21b.log',
 'dictionary-empty-attributes-7d56080.log', 'native-working-21b.log', 'native-working-21b.md',
 'read-fixes-working-21b-dictionary-fallback.log', 'read-fixes-working-21b-dictionary-parity.log'
]
for name in selected:
    copy(v / name, 'diagnosis/' + name)
index = dict(policy='Copied source bytes unchanged; no binaries or source archives included. Original absolute validation paths are retained for provenance.', files=entries)
with (base / 'qualification/implementation-evidence-index.json').open('x') as stream:
    json.dump(index, stream, indent=2)
print('Archived', len(entries), 'files;', sum(x['bytes'] for x in entries), 'bytes')

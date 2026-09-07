"""Copy ordinary review-supplement artifacts with exact bytes and source modes."""
from pathlib import Path
import hashlib
import json
import stat

VALIDATION = Path('/private/tmp/dta-direct-stage4-validation')
FOLLOWUP = VALIDATION / 'evidence-review-followup'
TARGET = Path('/private/tmp/dta-direct-stage4-review-supplement/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-supplement')
OLD = Path('/private/tmp/dta-direct-stage4-evidence/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4')


def copy(source, name):
    """Copy once or verify an earlier identical copy, including Unix permissions."""
    data = source.read_bytes()
    if source.is_symlink():
        raise RuntimeError('Symlink source')
    destination = TARGET / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(source.stat().st_mode)
    if destination.exists():
        if destination.read_bytes() != data or stat.S_IMODE(destination.stat().st_mode) != mode:
            raise RuntimeError('Changed existing copy ' + str(destination))
    else:
        with destination.open('xb') as stream:
            stream.write(data)
        destination.chmod(mode)
    return {'source': str(source), 'copy': name, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'unix_mode': format(mode, '04o'),
            'git_mode': '100755' if mode & 0o111 else '100644'}


rows = []
draft = json.loads((FOLLOWUP / 'source-selection.json').read_text())
for record in draft['files']:
    name = record['path'].replace('fixture-replay/', 'native-fixtures/', 1)
    row = copy(Path(record['original']), name)
    if row['bytes'] != record['bytes'] or row['sha256'] != record['sha256']:
        raise RuntimeError('Previously inventoried source changed')
    if 'existing_archive_path' in record:
        row.update({key: record[key] for key in ('existing_archive_path', 'existing_archive_mode', 'existing_archive_git_executable_mode')})
    rows.append(row)
for name in ('aggregate-read-diagnosis.R', 'atomic-accessor-diagnosis.R'):
    rows.append(copy(OLD / 'diagnosis' / name, 'diagnosis/' + name))
rows.append(copy(FOLLOWUP / 'diagnostic-guards-v2-executed-tool.py', 'supplement-source/diagnostic-guards-v2-executed-tool.py'))
rows.append(copy(FOLLOWUP / 'source-selection.json', 'supplement-source/source-selection.json'))
rows.append(copy(FOLLOWUP / 'assemble-normal-supplement.py', 'supplement-source/assemble-normal-supplement.py'))
manifest = {'format': 1, 'scope': 'Supplemental review evidence only; package remains Stage3 in this branch.',
            'base': 'ec10a6ac34602f3bd691e8043019c1b479babda4',
            'reviewed_historical_evidence': '5173f39b9b1bf895c4ced776b83db276e4593bc1',
            'qualified_package_source': 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15',
            'package_tree': 'f12a2a1dd430636a33b7f6e953023d90d1ff2589',
            'missing_referenced_review_artifacts': 29, 'original_mode_command_fixtures': 16,
            'copy_policy': 'Exact bytes and full retained-source Unix modes. Git records only regular-file/executable intent as100644/100755. Historical5173 artifacts remain unchanged.',
            'historical_link_context': draft['historical_links'],
            'files': rows}
with (TARGET / 'index.json').open('x') as stream:
    json.dump(manifest, stream, indent=2)
    stream.write('\n')
print('Copied',len(rows),'artifacts;',sum(r['bytes'] for r in rows),'bytes')

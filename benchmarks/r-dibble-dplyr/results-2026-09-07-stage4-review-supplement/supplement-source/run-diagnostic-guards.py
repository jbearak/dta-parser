"""Check explicit-library replay boundaries and record separate fresh replays."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
TOOL = Path('/private/tmp/dta-direct-stage4-evidence/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/review-supplement.py')
REPO = Path('/private/tmp/dta-direct-stage4')
LIBRARY = Path('/private/tmp/dta-direct-stage4-validation/candidate-e343b3b-library')
SOURCE = 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15'
OUTPUT = ROOT / 'diagnostic-guards-v2'
OUTPUT.mkdir()
(OUTPUT / 'empty-library').mkdir()
DLL = LIBRARY / 'dtatools/libs/dtatools.so'

def digest(path):
    """Hash exact source or output bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()

def require(value, message):
    """Fail closed without Python assertion optimization differences."""
    if not value:
        raise RuntimeError(message)

before = {str(p): digest(p) for p in [TOOL, DLL, *sorted((REPO / 'benchmarks/r-dibble-dplyr').glob('*helpers.R'))]}
env = os.environ.copy()
env['R_LIBS_USER'] = str(LIBRARY)
records = []
for kind in ('aggregate', 'accessor'):
    for case in ('valid-check', 'missing-library', 'wrong-source', 'changed-transitive-helper', 'valid-replay'):
        directory = OUTPUT / (kind + '-' + case)
        directory.mkdir()
        library, source, repository = LIBRARY, SOURCE, REPO
        if case == 'missing-library':
            library = OUTPUT / 'empty-library'
        if case == 'wrong-source':
            source = '0' * 40
        if case == 'changed-transitive-helper':
            repository = directory / 'repository'
            destination = repository / 'benchmarks/r-dibble-dplyr'
            destination.mkdir(parents=True)
            for name in ('helpers.R', 'owned-atomic-helpers.R', 'owned-double-helpers.R'):
                shutil.copy2(REPO / 'benchmarks/r-dibble-dplyr' / name, destination / name)
            with (destination / 'owned-double-helpers.R').open('a') as stream:
                stream.write('\n# Deliberate rejected transitive dependency change.\n')
        command = [sys.executable, str(TOOL), 'diagnose', kind, '--library', str(library),
                   '--source', source, '--repository', str(repository)]
        csv = directory / 'result.csv'
        if kind == 'accessor':
            command += ['--csv', str(csv)]
        if case != 'valid-replay':
            command += ['--check-only']
        process = subprocess.run(command, env=env, capture_output=True)
        (directory / 'stdout.log').write_bytes(process.stdout)
        (directory / 'stderr.log').write_bytes(process.stderr)
        success = case in ('valid-check', 'valid-replay')
        require((process.returncode == 0) == success, 'Unexpected outcome ' + kind + '-' + case)
        if not success:
            require(process.stdout == b'' and not csv.exists(), 'Rejected case produced output')
            expected = {'missing-library': b'Requested library has no dtatools installation',
                        'wrong-source': b'SOURCE_SHA does not match installation provenance',
                        'changed-transitive-helper': b'Changed diagnostic dependency:'}[case]
            require(expected in process.stderr, 'Wrong rejection reason')
        else:
            require(b'GUARDED REPLAY e343b3b' in process.stdout, 'Missing guarded identity')
        if case == 'valid-replay' and kind == 'accessor':
            require(csv.is_file(), 'Missing successful replay result')
        elif csv.exists():
            raise RuntimeError('Unexpected CSV')
        records.append({'kind': kind, 'case': case, 'command': command, 'exit_code': process.returncode,
                        'stdout_sha256': digest(directory / 'stdout.log'),
                        'stderr_sha256': digest(directory / 'stderr.log'),
                        'csv_sha256': digest(csv) if csv.exists() else None})
        print(kind, case, process.returncode, flush=True)
after = {name: digest(Path(name)) for name in before}
require(after == before, 'Source or installed DLL changed')
manifest = {'scope': 'New guarded replay qualification only; original development logs are unchanged and not retrospectively source-qualified',
            'source': SOURCE, 'tool_and_dependency_before': before, 'tool_and_dependency_after': after,
            'fallback_library_environment': {'R_LIBS_USER': str(LIBRARY)}, 'cases': records}
with (OUTPUT / 'manifest.json').open('x') as stream:
    json.dump(manifest, stream, indent=2)
    stream.write('\n')

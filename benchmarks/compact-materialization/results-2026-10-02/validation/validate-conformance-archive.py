import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

repository, package, prefix = map(Path, sys.argv[1:4])
commit = sys.argv[4]
log = prefix.with_suffix('.log').read_text()
if 'R package conformance: PASS (current source built and checked with offline Cargo archive)' not in log:
    raise RuntimeError('Required conformance did not report success')
files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', commit, '--',
    'r-package/dtatools/src', 'r-package/dtatools/R', 'r-package/dtatools/tests',
    'r-package/dtatools/tools'], cwd=repository, text=True).splitlines()
ignored = ('src/dta-tools/examples/', 'src/dta-tools/target/', 'src/dta-tools/tests/',
           'src/rust/target/', 'src/rust/v/')
ignored_files = ('src/Makevars', 'src/Makevars.win', 'tests/testthat/testthat-problems.rds')
excluded, checked = [], {}
archive_path = prefix.with_suffix('.tar.gz')
with tarfile.open(archive_path, 'r:gz') as archive:
    for path in files:
        relative = Path(path).relative_to('r-package/dtatools').as_posix()
        if relative.startswith(ignored) or relative in ignored_files:
            excluded.append(relative)
            continue
        expected = hashlib.sha256((package / relative).read_bytes()).hexdigest()
        member = archive.extractfile('dtatools/' + relative)
        actual = hashlib.sha256(member.read()).hexdigest()
        if actual != expected:
            raise RuntimeError('Checked source mismatch: ' + relative)
        checked[relative] = actual
record = dict(source_commit=commit, required_conformance_passed=True,
    source_archive_sha256=hashlib.sha256(archive_path.read_bytes()).hexdigest(),
    buildignore_sha256=hashlib.sha256((package / '.Rbuildignore').read_bytes()).hexdigest(),
    verified_files=checked, deliberately_excluded_by_buildignore=excluded,
    checked_source_matches_clean_export=True)
prefix.with_suffix('.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
print('PASS:', len(checked), 'packaged source files match; explicit Rbuildignore exclusions:',
      len(excluded), flush=True)

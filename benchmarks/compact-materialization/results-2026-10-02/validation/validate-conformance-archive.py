import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

repository, package, prefix = map(Path, sys.argv[1:4])
commit = sys.argv[4]
log = prefix.with_suffix('.log').read_text()
if 'R package conformance: PASS (current source built and checked with offline Cargo archive)' not in log:
    raise RuntimeError('Required conformance did not report success')
git_environment = {key: value for key, value in os.environ.items()
                   if not key.startswith('GIT_')}
files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', commit, '--',
    'r-package/dtatools/src', 'r-package/dtatools/R', 'r-package/dtatools/tests',
    'r-package/dtatools/tools'], cwd=repository, env=git_environment,
    text=True).splitlines()
ignored = ('src/dta-tools/examples/', 'src/dta-tools/target/', 'src/dta-tools/tests/',
           'src/rust/target/', 'src/rust/v/')
ignored_files = ('src/Makevars', 'src/Makevars.win', 'tests/testthat/testthat-problems.rds')
excluded, checked = [], {}
archive_path = prefix.with_suffix('.tar.gz')
with tarfile.open(archive_path, 'r:gz') as archive:
    scoped_members = {}
    for member in archive.getmembers():
        if member.isdir() or not member.name.startswith(
                ('dtatools/src/', 'dtatools/R/', 'dtatools/tests/', 'dtatools/tools/')):
            continue
        relative = member.name.removeprefix('dtatools/')
        if relative in scoped_members:
            raise RuntimeError('Duplicate packaged source: ' + relative)
        if not member.isfile():
            raise RuntimeError('Non-regular packaged source: ' + relative)
        scoped_members[relative] = member
    for path in files:
        relative = Path(path).relative_to('r-package/dtatools').as_posix()
        if relative.startswith(ignored) or relative in ignored_files:
            excluded.append(relative)
            continue
        expected = hashlib.sha256((package / relative).read_bytes()).hexdigest()
        if relative not in scoped_members:
            raise RuntimeError('Missing packaged source: ' + relative)
        member = archive.extractfile(scoped_members[relative])
        actual = hashlib.sha256(member.read()).hexdigest()
        if actual != expected:
            raise RuntimeError('Checked source mismatch: ' + relative)
        checked[relative] = actual
    unexpected = set(scoped_members) - set(checked)
    if unexpected:
        raise RuntimeError('Unexpected packaged source: ' + ', '.join(sorted(unexpected)))
record = dict(source_commit=commit, required_conformance_passed=True,
    source_archive_sha256=hashlib.sha256(archive_path.read_bytes()).hexdigest(),
    buildignore_sha256=hashlib.sha256((package / '.Rbuildignore').read_bytes()).hexdigest(),
    verified_files=checked, deliberately_excluded_by_buildignore=excluded,
    checked_source_matches_clean_export=True, exact_packaged_source_inventory=True,
    repository_environment_overrides_removed=True)
prefix.with_suffix('.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
print('PASS:', len(checked), 'packaged source files match; explicit Rbuildignore exclusions:',
      len(excluded), flush=True)

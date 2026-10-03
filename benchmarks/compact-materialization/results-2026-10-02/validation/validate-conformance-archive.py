import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile

repository, package, prefix = map(Path, sys.argv[1:4])
commit = sys.argv[4]
if re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', commit) is None:
    raise RuntimeError('source_commit must be a full Git object ID')
log = prefix.with_suffix('.log').read_text()
if 'R package conformance: PASS (current source built and checked with offline Cargo archive)' not in log:
    raise RuntimeError('Required conformance did not report success')
git_environment = {key: value for key, value in os.environ.items()
                   if not key.startswith('GIT_')}
git = ['git', '--no-replace-objects']
if subprocess.check_output(git + ['cat-file', '-t', commit], cwd=repository,
                           env=git_environment).strip() != b'commit':
    raise RuntimeError('source_commit does not identify a commit')
tree = subprocess.check_output(git + ['ls-tree', '-rz', commit, '--',
    'r-package/dtatools/src', 'r-package/dtatools/R', 'r-package/dtatools/tests',
    'r-package/dtatools/tools', 'r-package/dtatools/.Rbuildignore'],
    cwd=repository, env=git_environment)
entries = []
for entry in tree.split(b'\0'):
    if not entry:
        continue
    header, path = entry.split(b'\t', 1)
    mode, kind, object_id = header.split()
    if kind != b'blob' or mode not in (b'100644', b'100755'):
        raise RuntimeError('Source commit contains a non-regular file: ' + path.decode())
    entries.append((path.decode(), object_id))
if not entries:
    raise RuntimeError('Source commit has no package files')
# Read the immutable objects in one batch. The clean export and archive must
# each agree with these bytes; agreement with one another alone is insufficient.
objects = subprocess.check_output(git + ['cat-file', '--batch'], cwd=repository,
    env=git_environment, input=b''.join(object_id + b'\n' for _, object_id in entries))
committed, cursor = {}, 0
for path, object_id in entries:
    end = objects.index(b'\n', cursor)
    actual_id, kind, size = objects[cursor:end].split()
    size = int(size)
    cursor = end + 1
    data = objects[cursor:cursor + size]
    if actual_id != object_id or kind != b'blob' or len(data) != size or objects[cursor + size:cursor + size + 1] != b'\n':
        raise RuntimeError('Invalid Git blob response: ' + path)
    cursor += size + 1
    relative = Path(path).relative_to('r-package/dtatools').as_posix()
    digest = hashlib.sha256(data).hexdigest()
    if hashlib.sha256((package / relative).read_bytes()).hexdigest() != digest:
        raise RuntimeError('Clean export differs from source commit: ' + relative)
    committed[relative] = digest
if cursor != len(objects) or '.Rbuildignore' not in committed:
    raise RuntimeError('Incomplete committed-source inventory')
ignored = ('src/dta-tools/examples/', 'src/dta-tools/target/', 'src/dta-tools/tests/',
           'src/rust/target/', 'src/rust/v/')
ignored_files = ('src/Makevars', 'src/Makevars.win', 'tests/testthat/testthat-problems.rds')
excluded, checked = [], {}
archive_path = prefix.with_suffix('.tar.gz')
with tarfile.open(archive_path, 'r:gz') as archive:
    scoped_members = {}
    roots = ('dtatools/src', 'dtatools/R', 'dtatools/tests', 'dtatools/tools')
    for member in archive.getmembers():
        if member.isdir() or not (member.name in roots or
                member.name.startswith(tuple(root + '/' for root in roots))):
            continue
        relative = member.name.removeprefix('dtatools/')
        if relative in scoped_members:
            raise RuntimeError('Duplicate packaged source: ' + relative)
        if not member.isfile():
            raise RuntimeError('Non-regular packaged source: ' + relative)
        scoped_members[relative] = member
    for relative, expected in committed.items():
        if relative == '.Rbuildignore':
            continue
        if relative.startswith(ignored) or relative in ignored_files:
            excluded.append(relative)
            continue
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
    buildignore_sha256=committed['.Rbuildignore'],
    verified_files=checked, deliberately_excluded_by_buildignore=excluded,
    checked_source_matches_clean_export=True, exact_packaged_source_inventory=True,
    repository_environment_overrides_removed=True, clean_export_matches_source_commit=True,
    expected_hashes_from_committed_blobs=True)
prefix.with_suffix('.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
print('PASS:', len(checked), 'packaged source files match; explicit Rbuildignore exclusions:',
      len(excluded), flush=True)

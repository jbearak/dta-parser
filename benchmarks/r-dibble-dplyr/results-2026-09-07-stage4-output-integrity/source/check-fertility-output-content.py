"""Repeat exact-c8 downstream qualification with streamed output content guards.

This does not activate renv or change project files. It preserves the earlier
metadata-only evidence and gives only this new run a before/after SHA-256 proof.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import stat
import subprocess
import sys

ROOT = Path('/private/tmp/dta-direct-stage4-validation')
SOURCE = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
LIBRARY = ROOT / 'candidate-c8ca0a4-library'
DRIVER = ROOT / 'check-fertility-candidate.py'
PROJECT = Path('/Users/jmb/repos/fertility_surveys')
INTEGRATION_OUTPUT = PROJECT / 'output/mics.dta'


def require(condition, message):
    """Fail a provenance or preservation check under all Python modes."""
    if not condition:
        raise RuntimeError(message)


def digest(path):
    """Hash a small execution input without normalizing its bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, record):
    """Create a new record after its complete content has been computed."""
    with path.open('x') as stream:
        json.dump(record, stream, indent=2)
        stream.write('\n')


def file_identity(value):
    """Select content-relevant file identity fields, excluding read access time."""
    return {'device': value.st_dev, 'inode': value.st_ino,
            'size': value.st_size, 'mtime_ns': value.st_mtime_ns,
            'ctime_ns': value.st_ctime_ns,
            'mode': oct(stat.S_IMODE(value.st_mode))}


def content_snapshot(path):
    """Stream all bytes and reject file replacement or mutation during hashing."""
    require(not path.is_symlink(), 'Integration output must be a regular file')
    started = datetime.now(timezone.utc).isoformat()
    path_stat = path.stat()
    require(stat.S_ISREG(path_stat.st_mode), 'Integration output is not regular')
    path_before = file_identity(path_stat)
    hasher = hashlib.sha256()
    total = 0
    with path.open('rb') as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode), 'Integration output is not regular')
        require(file_identity(before) == path_before, 'Integration output replaced before hashing')
        while chunk := stream.read(8 * 1024 * 1024):
            hasher.update(chunk)
            total += len(chunk)
        after = os.fstat(stream.fileno())
    require(not path.is_symlink(), 'Integration output became a symlink')
    require(file_identity(before) == file_identity(after) == file_identity(path.stat()),
            'Integration output changed during hashing')
    require(total == before.st_size, 'Incomplete integration output read')
    return {'path': str(path), 'sha256': hasher.hexdigest(), 'bytes_read': total,
            'stat': file_identity(after), 'hash_started_utc': started,
            'hash_completed_utc': datetime.now(timezone.utc).isoformat()}


def main():
    """Run the unchanged child once, always recording the post-run content hash."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path,
                        help='New fertility-content-* directory directly under validation root')
    args = parser.parse_args()
    output = args.output.resolve()
    require(output.parent == ROOT.resolve() and output.name.startswith('fertility-content-'),
            'Evidence must be a new fertility-content-* child of the validation root')
    require(not output.exists(), 'Refusing to replace output evidence')
    committed_path = ('benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix/'
                      'qualification/source/check-fertility-candidate.py')
    committed = subprocess.check_output(
        ['git', 'show', 'f043959b3c1337fb6c49518a644171fed6067966:' + committed_path],
        cwd='/private/tmp/dta-direct-stage4-fix-qualification')
    require(DRIVER.read_bytes() == committed, 'Child driver differs from reviewed A blob')
    inputs = [Path(__file__).resolve(), DRIVER,
              Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R'),
              Path('/private/tmp/dta-direct-stage3-validation/resume-audit/fertility-stage2-baseline.log'),
              Path('/private/tmp/dta-direct-stage3-validation/resume-audit/fertility-before-exact-45f2ba4.json'),
              LIBRARY / 'dtatools/libs/dtatools.so',
              LIBRARY / 'dtatools/Meta/benchmark-provenance.rds']
    identities = {str(path): digest(path) for path in inputs}
    # Bind current inputs to the already reviewed c8 records, including its
    # native library and sidecar, rather than trusting a newly computed label.
    reviewed_records = []
    for relative, field in [
            ('qualification/fertility/input-identities.json', 'inputs'),
            ('diagnosis/root-probes-final/input-identities.json', None)]:
        path = ('benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix/' + relative)
        data = subprocess.check_output(
            ['git', 'show', 'f043959b3c1337fb6c49518a644171fed6067966:' + path],
            cwd='/private/tmp/dta-direct-stage4-fix-qualification')
        record = json.loads(data)
        recorded = record[field] if field else record
        selected = {name: value for name, value in recorded.items() if name in identities}
        for name, expected in selected.items():
            require(identities[name] == expected, 'Input differs from reviewed c8 evidence')
        reviewed_records.append({'git_path': path, 'sha256': hashlib.sha256(data).hexdigest(),
                                 'checked_input_paths': sorted(selected)})
    covered = {name for record in reviewed_records for name in record['checked_input_paths']}
    require(covered == set(identities) - {str(Path(__file__).resolve())},
            'An executed input lacks its historical reviewed binding')
    output.mkdir(parents=True)
    dump(output / 'input-identities.json',
         {'files': identities, 'source': SOURCE, 'library': str(LIBRARY),
          'child_driver_git_revision': 'f043959b3c1337fb6c49518a644171fed6067966',
          'child_driver_git_path': committed_path, 'python': sys.version,
          'python_executable': sys.executable, 'reviewed_input_records': reviewed_records})
    before = content_snapshot(INTEGRATION_OUTPUT)
    dump(output / 'content-before.json', before)
    command = [sys.executable, str(DRIVER), SOURCE, str(LIBRARY), str(output / 'run')]
    result = None
    child_started = datetime.now(timezone.utc).isoformat()
    try:
        with (output / 'launch.log').open('xb') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    finally:
        child_finished = datetime.now(timezone.utc).isoformat()
        after = content_snapshot(INTEGRATION_OUTPUT)
        dump(output / 'content-after.json', after)
    child_path = output / 'run/verification.json'
    child = json.loads(child_path.read_text()) if child_path.is_file() else None
    inputs_unchanged = all(digest(Path(path)) == value for path, value in identities.items())
    content_unchanged = before['sha256'] == after['sha256']
    stat_unchanged = before['stat'] == after['stat']
    state_unchanged = bool(child and child['downstream_state_unchanged'] and
                           content_unchanged and stat_unchanged)
    record = {'source': SOURCE, 'command': command,
              'child_exit_code': result.returncode,
              'child_started_utc': child_started, 'child_finished_utc': child_finished,
              'output_content_sha256_unchanged': content_unchanged,
              'output_stat_unchanged': stat_unchanged,
              'downstream_state_unchanged': state_unchanged,
              'inputs_unchanged': inputs_unchanged,
              'child_complete_test_log_matches_baseline':
                  child['complete_test_log_matches_baseline'] if child else None,
              'scope': 'Fresh isolated-c8 repeat only. SHA-256 covers every output byte '
                       'at the two checkpoints of this run; it does not exclude transient '
                       'writes that restore the original bytes. Historical metadata-only records '
                       'are unchanged and gain no retrospective content digest. '
                       'No renv activation/install/restore or project source/output edits.',
              'files': {str(path.relative_to(output)): digest(path)
                        for path in sorted(output.rglob('*')) if path.is_file()}}
    # Construct the inventory before opening its destination; never self-hash.
    dump(output / 'content-verification.json', record)
    require(inputs_unchanged, 'Execution input changed')
    require(state_unchanged, 'Downstream file content or recorded state changed')
    require(child is not None and result.returncode == 0,
            'Child qualification did not pass; inspect its preserved complete outputs')
    print('PASS: fresh c8 downstream state and full integration-output SHA-256 unchanged')


if __name__ == '__main__':
    main()

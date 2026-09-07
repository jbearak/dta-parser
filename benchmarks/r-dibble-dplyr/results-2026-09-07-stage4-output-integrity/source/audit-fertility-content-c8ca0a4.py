"""Independently check the completed fresh content-guarded downstream records."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re

ROOT = Path('/private/tmp/dta-direct-stage4-validation')
DATA = ROOT / 'fertility-content-c8ca0a4'


def require(value, message):
    """Reject any incomplete or inconsistent retained evidence."""
    if not value:
        raise RuntimeError(message)


def digest(path):
    """Hash the complete bytes of a small evidence or execution-input file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    """Check provenance, all recorded hashes, strict log parity and hash ordering."""
    content = json.loads((DATA / 'content-verification.json').read_text())
    child = json.loads((DATA / 'run/verification.json').read_text())
    before = json.loads((DATA / 'content-before.json').read_text())
    after = json.loads((DATA / 'content-after.json').read_text())
    identities = json.loads((DATA / 'input-identities.json').read_text())
    require(digest(ROOT / 'check-fertility-output-content.py') ==
            'e6a1e2372e77d06707451db86e51fd5ae4323bfc308388c5cb3ed44f88f5b6aa',
            'Reviewed wrapper changed')
    for base, record in [(DATA, content), (DATA / 'run', child)]:
        for relative, expected in record['files'].items():
            path = base / relative
            require(path.is_file() and not path.is_symlink(), 'Missing regular evidence')
            require(digest(path) == expected, 'Recorded file hash mismatch')
    require(set(content['files']) == {
        str(p.relative_to(DATA)) for p in DATA.rglob('*')
        if p.is_file() and p.name != 'content-verification.json'}, 'Incomplete content inventory')
    for path, expected in identities['files'].items():
        require(digest(Path(path)) == expected, 'Execution input changed')
    require(content['source'] == child['source_sha'] == identities['source'] ==
            'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe', 'Wrong source')
    require(content['child_exit_code'] == 0 and child['test_exit_code'] == 1 and
            child['post_install_guard_exit_code'] == 0, 'Wrong process status')
    require(before['sha256'] == after['sha256'] and before['stat'] == after['stat'] and
            before['bytes_read'] == after['bytes_read'] == before['stat']['size'] == 4374755735,
            'Content checkpoints disagree')
    times = [before['hash_started_utc'], before['hash_completed_utc'],
             content['child_started_utc'], content['child_finished_utc'],
             after['hash_started_utc'], after['hash_completed_utc']]
    require([datetime.fromisoformat(t) for t in times] ==
            sorted(datetime.fromisoformat(t) for t in times), 'Invalid checkpoint ordering')
    require((DATA / 'run/before.json').read_bytes() == (DATA / 'run/after.json').read_bytes(),
            'Project snapshots differ')
    state = json.loads((DATA / 'run/before.json').read_text())
    require(len(state['files']) == child['source_file_count'] == 454, 'Wrong file coverage')
    actual = (DATA / 'run/test.log').read_bytes()
    baseline = Path('/private/tmp/dta-direct-stage3-validation/resume-audit/fertility-stage2-baseline.log').read_bytes()
    marker = b'backend: r'
    require(actual[actual.index(marker):] == baseline[baseline.index(marker):], 'Baseline bytes differ')
    require(actual[:actual.index(marker)] ==
            b'Exact source c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe\nDLL_md5 c655c59a09cbf1cd72a6f72e7e94758e\n',
            'Wrong identity header')
    require(re.findall(rb'r backend: (\d+) tests, (\d+) failed or errored, (\d+) skipped', actual) ==
            [(b'499', b'4', b'2')], 'Wrong test summary')
    require(b'Column reallocation' not in actual, 'Unexpected allocation warning')
    require(all(content[k] is True for k in [
        'output_content_sha256_unchanged', 'output_stat_unchanged',
        'downstream_state_unchanged', 'inputs_unchanged',
        'child_complete_test_log_matches_baseline']), 'Inconsistent pass predicates')
    record = {'completed_utc': datetime.now(timezone.utc).isoformat(),
              'result': 'pass', 'auditor_sha256': digest(Path(__file__)),
              'content_verification_sha256': digest(DATA / 'content-verification.json'),
              'all_run_files': {str(p.relative_to(DATA)): digest(p)
                               for p in sorted(DATA.rglob('*')) if p.is_file()},
              'outer_launch_log_sha256': digest(ROOT / 'fertility-content-c8ca0a4-launch.log'),
              'scope': 'Independent retained-record and current-input audit. No R rerun, '
                       'real-output rehash, renv change, or historical evidence modification.'}
    with (ROOT / 'root-fertility-content-c8ca0a4-audit.json').open('x') as stream:
        json.dump(record, stream, indent=2)
        stream.write('\n')
    print('PASS: all 12 run records, strict baseline log, 454-file snapshots and input identities agree')


if __name__ == '__main__':
    main()

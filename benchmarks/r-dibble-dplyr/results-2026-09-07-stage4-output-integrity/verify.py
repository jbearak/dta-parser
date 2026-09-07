"""Verify this additive output-content archive without R or reading mics.dta."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess


def require(condition, message):
    """Reject incomplete or changed evidence independently of Python optimization."""
    if not condition:
        raise RuntimeError(message)


def digest(data):
    """Hash the exact stored artifact bytes."""
    return hashlib.sha256(data).hexdigest()


def contained(root, relative):
    """Resolve an ordinary archive file without following escaping paths or links."""
    path = root / relative
    require(not Path(relative).is_absolute() and '..' not in Path(relative).parts,
            'Invalid archive path: ' + relative)
    require(not path.is_symlink() and path.is_file() and path.resolve().is_relative_to(root),
            'Missing, escaping or nonregular file: ' + relative)
    return path


def embedded(root, relative):
    """Check the complete child manifest inventory, excluding only its own file."""
    path = contained(root, relative)
    record = json.loads(path.read_text())
    expected = {str(p.relative_to(path.parent)) for p in path.parent.rglob('*') if p.is_file() and p != path}
    require(set(record['files']) == expected, 'Incomplete embedded inventory: ' + relative)
    for name, expected_sha in record['files'].items():
        actual = contained(root, str(path.parent.relative_to(root) / name))
        require(digest(actual.read_bytes()) == expected_sha, 'Changed embedded output: ' + name)
    return record


def verify(root, git_repo=None):
    """Verify copied bytes, endpoint order, child result and optional fixed Git inputs.

    The endpoint records cover the fresh run only. This verifier does not read
    the multi-gigabyte external output or establish absence of transient writes.
    """
    root = root.resolve()
    index = json.loads(contained(root, 'index.json').read_text())
    indexed = index['files']
    names = [r['path'] for r in indexed]
    require(len(names) == len(set(names)) and 'index.json' not in names, 'Invalid index path set')
    actual = set()
    for path in root.rglob('*'):
        require(not path.is_symlink(), 'Archive symlink: ' + str(path))
        if path.is_file():
            actual.add(str(path.relative_to(root)))
        else:
            require(path.is_dir(), 'Archive contains a special file')
    require(actual == set(names) | {'index.json'}, 'Archive file set mismatch')
    for row in indexed:
        path = contained(root, row['path'])
        require(path.stat().st_size == row['bytes'] and digest(path.read_bytes()) == row['sha256'],
                'Changed archive bytes: ' + row['path'])
        mode = '100755' if path.stat().st_mode & 0o111 else '100644'
        require(mode == row['git_mode'], 'Changed executable mode: ' + row['path'])
    outer = embedded(root, 'run/content-verification.json')
    child = embedded(root, 'run/run/verification.json')
    before = json.loads(contained(root, 'run/content-before.json').read_text())
    after = json.loads(contained(root, 'run/content-after.json').read_text())
    require(before['path'] == after['path'] and before['sha256'] == after['sha256'] and
            re.fullmatch('[0-9a-f]{64}', before['sha256']) and before['stat'] == after['stat'] and
            before['bytes_read'] == after['bytes_read'] == before['stat']['size'] == 4374755735,
            'Output endpoint mismatch')
    times = [before['hash_started_utc'], before['hash_completed_utc'], outer['child_started_utc'],
             outer['child_finished_utc'], after['hash_started_utc'], after['hash_completed_utc']]
    require([datetime.fromisoformat(t) for t in times] == sorted(datetime.fromisoformat(t) for t in times),
            'Invalid observation order')
    require(outer['child_exit_code'] == 0 and all(outer[k] is True for k in
            ['output_content_sha256_unchanged', 'output_stat_unchanged', 'downstream_state_unchanged',
             'inputs_unchanged', 'child_complete_test_log_matches_baseline']), 'Outer qualification did not pass')
    require(child['tests_failed_blocks_skips'] == child['baseline_tests_failed_blocks_skips'] == [499, 4, 2] and
            child['test_exit_code'] == 1 and child['post_install_guard_exit_code'] == 0 and
            child['source_file_count'] == 454 and child['column_reallocation_warning_present'] is False and
            all(child[k] is True for k in ['complete_test_log_matches_baseline', 'prefix_matches_exact_identity_header',
                                         'downstream_state_unchanged', 'input_files_unchanged']), 'Child qualification did not pass')
    require(contained(root, 'run/run/before.json').read_bytes() == contained(root, 'run/run/after.json').read_bytes(),
            'Child state records differ')
    require(outer['source'] == child['source_sha'] == index['package_source'], 'Package identity mismatch')
    if git_repo:
        for row in index['git_inputs']:
            run = subprocess.run(['git', '-C', str(git_repo), 'show', row['revision'] + ':' + row['path']], capture_output=True)
            require(run.returncode == 0 and digest(run.stdout) == row['sha256'], 'Changed or missing Git input: ' + row['path'])
    return {'indexed_files': len(indexed), 'run_records': len(outer['files']) + 1,
            'endpoint_bytes': before['bytes_read'], 'endpoint_sha256': before['sha256'],
            'git_inputs_checked': len(index['git_inputs']) if git_repo else 0}


def main():
    """Print a read-only verification result; never create archive or workload output."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--git-repo', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(Path(__file__).resolve().parent, args.git_repo), indent=2))


if __name__ == '__main__':
    main()

"""Check this supplement and recheck its bindings against the unchanged archive."""
import argparse
import hashlib
import json
from pathlib import Path


def require(condition, message):
    """Reject missing, changed or inconsistent evidence in every Python mode."""
    if not condition:
        raise RuntimeError(message)


def digest(path):
    """Hash an ordinary evidence file without interpreting its contents."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    """Verify all supplement files and rerun only the read-only identity auditor."""
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=root.parent / 'results-2026-09-07-stage4-review-fix')
    args = parser.parse_args()
    index = json.loads((root / 'index.json').read_text())
    names = [r['path'] for r in index['files']]
    require(len(names) == len(set(names)) and 'index.json' not in names, 'Duplicate or self index entry')
    actual = set()
    for path in root.rglob('*'):
        require(not path.is_symlink(), 'Supplement contains a symlink')
        if path.is_file():
            actual.add(str(path.relative_to(root)))
        else:
            require(path.is_dir(), 'Supplement contains a special file')
    require(actual == set(names) | {'index.json'}, 'Supplement path set mismatch')
    for row in index['files']:
        path = root / row['path']
        require(not Path(row['path']).is_absolute() and '..' not in Path(row['path']).parts and
                path.resolve().is_relative_to(root), 'Escaping index path')
        require(path.is_file() and path.stat().st_size == row['bytes'] and digest(path) == row['sha256'],
                'Changed supplement bytes: ' + row['path'])
        require(('100755' if path.stat().st_mode & 0o111 else '100644') == row['git_mode'], 'Changed executable mode')
    helper = root / 'audit-comparison-bindings.py'
    namespace = {'__name__': 'reviewed_comparison_auditor', '__file__': str(helper)}
    exec(compile(helper.read_bytes(), str(helper), 'exec'), namespace)
    actual_receipt = namespace['audit'](args.archive)
    actual_receipt['auditor_sha256'] = digest(helper)
    expected = json.loads((root / 'actual-audit.json').read_text())
    require(actual_receipt == expected, 'Actual archived bindings differ from saved receipt')
    guards = json.loads((root / 'guards/summary.json').read_text())
    require(guards['auditor_sha256'] == digest(helper) and
            guards['test_sha256'] == digest(root / 'test-comparison-bindings.py'), 'Guard source identity mismatch')
    require([r['mode'] for r in guards['runs']] == ['default', 'dash-O', 'env-optimize'], 'Guard modes incomplete')
    count = 0
    for record in guards['runs']:
        path = root / 'guards' / (record['mode'] + '.json')
        require(digest(path) == record['sha256'], 'Changed guard output')
        result = json.loads(path.read_text())
        require(result['auditor_sha256'] == digest(helper) and result['auditor_mode'] == record['mode'], 'Guard mode/source mismatch')
        require(result['historical_source_sha256'] == digest(args.archive / 'benchmark/source/summarize-c8ca0a4-performance.py'),
                'Historical loop source differs')
        require(result['auditor_dash_O'] is (record['mode'] == 'dash-O') and
                result['auditor_PYTHONOPTIMIZE'] == ('1' if record['mode'] == 'env-optimize' else None), 'Optimization launch mismatch')
        cases = result['cases']
        require(len(cases) == record['cases'] == 29 and len({r['case'] for r in cases}) == 29, 'Incomplete guard cases')
        require(sum(r['case'] == 'valid' for r in cases) == 1 and
                all((r['exit_code'] == 0) == (r['case'] == 'valid') and r['inputs_unchanged'] is True for r in cases),
                'Guard result mismatch')
        require(sum(r['historical_exact_loop_admits_stale_identity'] is True for r in cases) == 9, 'Historical gap probes incomplete')
        count += len(cases)
    print(json.dumps({'verified_files': len(names) + 1, 'guard_cases': count,
                      'bound_input_files': len(expected['inputs_sha256']), 'comparisons': 3}, indent=2))


if __name__ == '__main__':
    main()

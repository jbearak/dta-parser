from pathlib import Path
import json, hashlib
root = Path('/private/tmp/dta-direct-stage4-validation')
baseline = Path('/private/tmp/dta-direct-stage3-validation/resume-audit/fertility-stage2-baseline.log')
output = root / 'fertility-e343b3b-praise-diagnosis' / 'semantic-parity-audit.json'
def require(test, message):
    if not test:
        raise RuntimeError(message)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
baseline_bytes = baseline.read_bytes()
marker = b'backend: r'
require(baseline_bytes.count(marker) == 1, 'Ambiguous baseline marker')
expected = baseline_bytes[baseline_bytes.index(marker):]
done_lines = [line for line in expected.splitlines(keepends=True) if line.startswith('══ DONE '.encode())]
require(len(done_lines) == 1, 'Ambiguous baseline DONE line')
encouragement = b'I believe in you!\n'
checks = []
for name in ['fertility-e343b3b', 'fertility-e343b3b-retry']:
    directory = root / name
    verification = json.loads((directory / 'verification.json').read_text())
    for file, sha in verification['files'].items():
        require(digest(directory / file) == sha, 'Changed saved artifact: ' + file)
    require(verification['source_sha'] == 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15', 'Wrong source')
    require(verification['tests_failed_blocks_skips'] == verification['baseline_tests_failed_blocks_skips'] == [499, 4, 2], 'Changed outcomes')
    require(verification['test_exit_code'] == 1 and verification['post_install_guard_exit_code'] == 0, 'Changed process status')
    for key in ['prefix_matches_exact_identity_header', 'downstream_state_unchanged', 'input_files_unchanged']:
        require(verification[key] is True, 'Failed original guard: ' + key)
    require(verification['source_file_count'] == 454, 'Incomplete downstream inventory')
    require(verification['column_reallocation_warning_present'] is False, 'Reallocation warning')
    require(verification['complete_test_log_matches_baseline'] is False, 'Original strict failure must remain recorded')
    actual_full = (directory / 'test.log').read_bytes()
    require(actual_full.count(marker) == 1, 'Ambiguous actual marker')
    actual = actual_full[actual_full.index(marker):]
    require(actual.count(encouragement) == 1, 'Unexpected encouragement count')
    index = actual.index(encouragement)
    require(actual[:index].endswith(done_lines[0]), 'Encouragement outside reporter footer')
    require(actual[index + len(encouragement):].startswith(b'\nr backend: 499 tests, 4 failed or errored, 2 skipped\n'), 'Unexpected footer position')
    without_footer_line = actual[:index] + actual[index + len(encouragement):]
    require(without_footer_line == expected, 'Another output difference exists')
    checks.append({'directory': str(directory), 'verification_sha256': digest(directory / 'verification.json'),
                   'raw_log_sha256': digest(directory / 'test.log'), 'strict_driver_result': 'rejected and preserved',
                   'test_outcomes_and_all_other_backend_bytes_match': True,
                   'only_difference': 'One exact testthat encouragement line immediately after DONE and before backend counts',
                   'full_raw_log_matches_baseline': False})
result = {'source_sha': 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15', 'baseline_sha256': digest(baseline),
          'auditor_sha256': digest(Path(__file__)), 'cases': checks,
          'scope': 'Read-only semantic/output parity audit of two existing runs; no R rerun, no raw evidence edits, no driver normalization or changed guards',
          'framework_source_log_sha256': digest(root / 'fertility-e343b3b-praise-diagnosis/framework-source.log')}
with output.open('x') as file:
    json.dump(result, file, indent=2)
    file.write('\n')
print(json.dumps(result, indent=2))

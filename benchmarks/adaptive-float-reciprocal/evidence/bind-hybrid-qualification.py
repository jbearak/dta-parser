#!/usr/bin/env python3
"""Bind the adaptive screen's existing untimed qualification, without running tests."""
import csv
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = Path('<measured-source>')
COMMIT = '2ec57f24a14a646ae67fd2e0af4fb8ef1c549f52'
TESTS = ('test-native-arithmetic-parity.R', 'test-arithmetic-payload-lifetime.R')


def require(value, message):
    if not value:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    def git(*args):
        return subprocess.check_output(['git', '--no-replace-objects', *args], cwd=SOURCE, env=env)

    source_files = ['r-package/dtatools/src/numeric-arithmetic-float-reciprocal.h',
                    'r-package/dtatools/tools/native-test-manifest.json']
    source_files += ['r-package/dtatools/tests/testthat/' + name for name in TESTS]
    source_hashes = {}
    for name in source_files:
        data = (SOURCE / name).read_bytes()
        require(data == git('show', COMMIT + ':' + name), 'Current source differs from frozen blob: ' + name)
        source_hashes[name] = hashlib.sha256(data).hexdigest()

    focused = {}
    expected_blocks = {(name, title) for name in TESTS for title in re.findall(
        r'test_that\("([^"\n]+)"',
        (SOURCE / 'r-package/dtatools/tests/testthat' / name).read_text())}
    require(len(expected_blocks) == 34, 'Frozen focused source matrix changed')
    for role in ('baseline', 'candidate'):
        path = HERE / ('hybrid-' + role + '-focused-v1.csv')
        rows = list(csv.DictReader(path.open()))
        require(len(rows) == 34 and len({(r['file'], r['test']) for r in rows}) == 34,
                'Focused block matrix changed')
        require({(r['file'], r['test']) for r in rows} == expected_blocks,
                'Focused results omit or replace a frozen source block')
        for row in rows:
            require(row['file'] in TESTS, 'Unexpected focused source')
            for name in ('passed', 'failed', 'warning'):
                require(re.fullmatch(r'[0-9]+', row[name]) is not None, 'Invalid focused count')
            require(row['failed'] == row['warning'] == '0' and
                    row['error'] == row['skipped'] == 'FALSE', 'Focused block did not pass')
        require(sum(int(r['passed']) for r in rows) == 36009, 'Focused assertion count changed')
        new = {r['test']: int(r['passed']) for r in rows if r['test'].startswith(
            ('adaptive reciprocal proofs', 'all missing reciprocal proofs'))}
        require(new == {'adaptive reciprocal proofs recover ordinary tails after dense spans': 1036,
                        'all missing reciprocal proofs retain captured counts through reentry': 100},
                'New focused obligations changed')
        focused[role] = {'assertions': 36009, 'blocks': 34, 'csv_sha256': sha(path),
                        'log_sha256': sha(path.with_suffix('.log')), 'new_blocks': new}

    structural = json.loads((HERE / 'hybrid-green-v1/receipt.json').read_text())
    require(structural['status'] == 'PASS' and structural['commit'] == COMMIT and
            structural['matrix_cases'] == 1980 and structural['semantic_failures'] == 0 and
            structural['work_failures'] == 0, 'Structural green receipt mismatch')
    for name, digest in structural['artifact_sha256'].items():
        require(sha(HERE / 'hybrid-green-v1' / name) == digest, 'Structural artifact changed')

    q = HERE / 'hybrid-qualification-v1'
    completion = json.loads((q / 'completion.json').read_text())
    require(completion['phase'] == 'qualify' and completion['observations'] == 36 and
            completion['exact_results'] is True and completion['provenance_unchanged'] is True,
            'No-clock qualification mismatch')
    for name, digest in completion['artifacts'].items():
        require(sha(q / name) == digest, 'Qualification artifact changed')
    before = json.loads((q / 'provenance-before.json').read_text())
    require(before == json.loads((q / 'provenance-after.json').read_text()), 'Qualification bindings changed')
    require(before['builds']['candidate']['receipt']['base_commit'] == COMMIT, 'Wrong candidate build')
    require(sha(HERE / 'candidate-v3/build-receipt.json') ==
            before['builds']['candidate']['receipt_sha256'], 'Candidate receipt differs from qualification')
    codegen = json.loads((HERE / 'codegen-v3/binding.json').read_text())
    require(codegen['source_commit'] == COMMIT and codegen['build_receipt_sha256'] ==
            before['builds']['candidate']['receipt_sha256'], 'Codegen build differs from qualification')
    require(codegen['installed_dll_sha256'] ==
            before['builds']['candidate']['installed']['libs/dtatools.so'], 'Codegen DLL differs from qualification')

    output = dict(source_commit=COMMIT, exact_source_sha256=source_hashes, focused=focused,
                  structural_receipt_sha256=sha(HERE / 'hybrid-green-v1/receipt.json'),
                  qualification_completion_sha256=sha(q / 'completion.json'),
                  candidate_build_receipt_sha256=sha(HERE / 'candidate-v3/build-receipt.json'),
                  codegen_binding_sha256=sha(HERE / 'codegen-v3/binding.json'),
                  binder_sha256=sha(Path(__file__)),
                  scope='Post-run binding of existing focused results and exact current committed test source. '
                        'Baseline f219 and candidate2ec57 executed the same final test source. '
                        'No full-suite, packaged archive or timing claim. Full build/runtime inventories are '
                        'separately retained in no-clock provenance and will be checked again by the timing controller.')
    (HERE / 'hybrid-qualification-binding.json').write_text(json.dumps(output, indent=2) + '\n')
    print('Bound adaptive focused, structural and no-clock qualification')


if __name__ == '__main__':
    main()

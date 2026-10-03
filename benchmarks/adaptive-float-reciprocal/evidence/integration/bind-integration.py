#!/usr/bin/env python3
"""Post-run qualification binding; executes no tests or timings."""
import csv
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

WORK = Path(__file__).resolve().parent
ROOT = Path('<integrated-source>')
MEASURED_WORK = Path('<measured-work>')
SOURCE = 'a93716003b553626e120a97fba0991ef73334b26'
PARENT = '213ceeee5a0f7953bf0f13316e2207a766dcbb24'
MEASURED = '2ec57f24a14a646ae67fd2e0af4fb8ef1c549f52'
FOCUSED = Path('<private-work>/dta-float-reciprocal-evidence/focused-source.R')


def require(value, message):
    if not value:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    def git(*args):
        return subprocess.check_output(['git', '--no-replace-objects', *args], cwd=ROOT, env=env)

    expected = {'src/numeric-arithmetic-float-reciprocal.h', 'tests/testthat/test-native-arithmetic-parity.R',
                'tests/testthat/test-arithmetic-payload-lifetime.R', 'tools/native-test-manifest.json'}
    changed = {p.removeprefix('r-package/dtatools/') for p in git(
        'diff', '--name-only', PARENT, SOURCE, '--', 'r-package/dtatools').decode().splitlines()}
    require(changed == expected, 'Unexpected integrated package delta')
    header = 'r-package/dtatools/src/numeric-arithmetic-float-reciprocal.h'
    require(git('show', SOURCE + ':' + header) == git('show', MEASURED + ':' + header), 'Measured header changed')
    for name in ('test-native-arithmetic-parity.R', 'test-arithmetic-payload-lifetime.R'):
        path = 'r-package/dtatools/tests/testthat/' + name
        require(git('show', SOURCE + ':' + path).startswith(git('show', PARENT + ':' + path)), 'Parent tests changed')

    spec = importlib.util.spec_from_file_location('records', ROOT / 'benchmarks/native-operations/run.py')
    records = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(records)
    inventory = records.inventory(WORK / 'integration-candidate', 'baseline')
    require(inventory['receipt']['base_commit'] == SOURCE and inventory['receipt']['source_patch_sha256'] ==
            hashlib.sha256(b'').hexdigest(), 'Wrong clean integration build')
    for name, digest in inventory['source'].items():
        require(hashlib.sha256(git('show', SOURCE + ':r-package/dtatools/' + name)).hexdigest() == digest,
                'Build source differs from integrated commit')
        require(sha(ROOT / 'r-package/dtatools' / name) == digest, 'Current package changed after qualification')

    rows = list(csv.DictReader((WORK / 'integration-focused.csv').open()))
    require(len(rows) == len({(r['file'], r['test']) for r in rows}) == 40, 'Focused matrix changed')
    expected_blocks = {(name, title) for name in
        ('test-native-arithmetic-parity.R', 'test-arithmetic-payload-lifetime.R')
        for title in re.findall(r'test_that\("([^"\n]+)"', git(
            'show', SOURCE + ':r-package/dtatools/tests/testthat/' + name).decode())}
    require({(r['file'], r['test']) for r in rows} == expected_blocks,
            'Focused results do not match the frozen source block set')
    for row in rows:
        require(all(re.fullmatch(r'[0-9]+', row[k]) for k in ('passed', 'failed', 'warning')), 'Malformed counts')
        require(row['failed'] == row['warning'] == '0' and row['error'] == row['skipped'] == 'FALSE', 'Focused failure')
    require(sum(int(r['passed']) for r in rows) == 38124, 'Focused assertion count changed')

    archive = json.loads((WORK / 'conformance.json').read_text())
    require(archive['source_commit'] == SOURCE and all(archive[k] is True for k in (
        'required_conformance_passed', 'expected_hashes_from_committed_blobs',
        'checked_source_matches_clean_export', 'clean_export_matches_source_commit',
        'exact_packaged_source_inventory', 'repository_environment_overrides_removed')), 'Archive gate failed')
    require(sha(WORK / 'conformance.tar.gz') == archive['source_archive_sha256'], 'Archive changed')
    command = json.loads((WORK / 'conformance-command.json').read_text())
    require(command['commit'] == SOURCE and command['exit_code'] == 0, 'Conformance command failed')
    for name, key in (('conformance-gate.sh', 'wrapper_sha256'), ('validate-conformance-archive.py', 'validator_sha256'),
                      ('conformance-export/scripts/conformance.sh', 'original_script_sha256')):
        require(sha(WORK / name) == command[key], 'Conformance controller changed')
    log = (WORK / 'conformance.log').read_text()
    require('R package conformance: PASS (current source built and checked with offline Cargo archive)' in log and
            'Status: 3 WARNINGs, 2 NOTEs' in log, 'Required check result changed')
    original = WORK / 'conformance-preserved/dtatools.Rcheck/tests/testthat.Rout'
    counts = re.findall(r'\[ FAIL ([0-9]+) \| WARN ([0-9]+) \| SKIP ([0-9]+) \| PASS ([0-9]+) \]', original.read_text())
    require(len(counts) == 2 and counts[0] == counts[1], 'Missing/inconsistent full-suite summaries')
    failed, warnings, skipped, passed = map(int, counts[0])
    require((failed, warnings, skipped) == (0, 7, 0) and passed > 103000, 'Full archived suite did not pass')
    target = WORK / 'conformance-testthat.Rout'
    if target.exists():
        require(target.read_bytes() == original.read_bytes(), 'Retained full output changed')
    else:
        shutil.copyfile(original, target)
    shutil.copyfile(FOCUSED, WORK / 'focused-source.R')
    files = ['integration-focused.csv', 'integration-focused.log', 'focused-source.R',
             'integration-candidate/build-receipt.json', 'integration-candidate/input-record.json',
             'conformance.json', 'conformance-command.json', 'conformance.log', 'conformance-testthat.Rout',
             'run-conformance.py', 'conformance-gate.sh', 'validate-conformance-archive.py', 'bind-integration.py']
    record = dict(status='PASS', source_commit=SOURCE, parent_commit=PARENT, measured_header_commit=MEASURED,
                  exact_package_delta=sorted(expected), parent_test_prefixes_preserved=True,
                  focused=dict(blocks=40, passed=38124, failed=0, skipped=0, warnings=0),
                  archived_suite=dict(passed=passed, failed=failed, skipped=skipped, warnings=warnings),
                  build=inventory, source_archive_sha256=archive['source_archive_sha256'],
                  focused_launch_supplement=dict(record_kind='Post-run invocation supplement',
                    command=['Rscript', '--vanilla', str(FOCUSED), str(WORK / 'integration-candidate/library'),
                             str(WORK / 'integration-focused.csv'), str(ROOT / 'r-package/dtatools/tests/testthat')],
                    cwd='<user>/.codex-workspaces/worktrees/066e8b87-8150-411f-be0d-6eb945a8955f/dta-parser'),
                  artifact_sha256={name: sha(WORK / name) for name in files},
                  scope='Measured header integrated unchanged on fixed PR301. Focused installed tests and full retained '
                        'archive testthat suite are separate qualifications; no new timing or separate full installed-suite claim. '
                        'Two identical final Rout summaries represent one full suite.')
    (WORK / 'integration-binding.json').write_text(json.dumps(record, indent=2) + '\n')
    print('PASS', record['focused'], record['archived_suite'])


if __name__ == '__main__':
    main()

"""Verify the completed R run, accepting each unchanged fixture's DLL label.

The launch coordinator expected DLL_md5 in every child, but three historical
fixtures print DLL. Their hashes were correct and all 219 R comparisons already
passed. Preserve that failed post-check and every raw output; audit them here.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path('/private/tmp/dta-direct-stage4-validation/root-acceptance-c8ca0a4')
CASES = {'generation-names': 45, 'delayed-mask': 72,
         'delayed-private-mask': 72, 'symbol-private-callback': 30}


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


inputs = json.loads((ROOT / 'input-identities.json').read_text())
require(all(digest(Path(path)) == expected for path, expected in inputs.items()),
        'A pre-run input changed')
driver = (ROOT / 'driver.log').read_text()
require('All 219 R-only root regression cases passed' in driver,
        'Missing completed R comparison result')
require('Exact package source c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe' in driver,
        'Wrong source identity')
records = []
for name, count in CASES.items():
    log = (ROOT / (name + '-candidate.log')).read_text()
    found = re.findall(r'^DLL(?:_md5)? ([0-9a-f]{32})\s*$', log, re.MULTILINE)
    require(found == ['c655c59a09cbf1cd72a6f72e7e94758e'], f'Wrong or ambiguous DLL: {name}')
    baseline = ROOT / (name + '-baseline.rds')
    candidate = ROOT / (name + '-candidate.rds')
    require(candidate.read_bytes() == baseline.read_bytes(), f'RDS mismatch: {name}')
    require(f'{name} {count} exact historical behavior comparisons passed' in driver,
            f'Missing exact case count: {name}')
    records.append({'name': name, 'cases': count, 'dll_md5': found[0],
                    'baseline_and_candidate_rds_sha256': digest(candidate)})
with (ROOT / 'post-run-audit.json').open('x') as stream:
    json.dump({'source_sha': 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe',
               'cases': records, 'inputs_unchanged': True,
               'raw_files': {p.name: digest(p) for p in ROOT.iterdir() if p.is_file()},
               'auditor_sha256': digest(Path(__file__)),
               'launch_coordinator_status': 'Failed post-run DLL label assertion, preserved.',
               'actual_R_result': 'All 219 comparisons passed; all four unchanged workload/oracle '
                                  'RDS files are byte-identical to baseline. Exact DLL hashes agree.',
               'scope': 'No test rerun and no raw file rewrite. Corrected parsing of historical '
                        'DLL and DLL_md5 labels only. Excludes the prior unavailable native observer.'},
              stream, indent=2)
    stream.write('\n')
print('All 219 R comparisons and four exact child DLL/RDS identities verified.')
